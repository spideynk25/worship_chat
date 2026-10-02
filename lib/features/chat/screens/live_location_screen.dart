import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/location_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/models/user_model.dart';

enum MapTileTheme {
  osmDark,
  esriDark,
  osmHumanitarian,
  cyclosm,
  esriSatellite,
  openStreetMap,
}

/// Represents an active participant sharing live location in this chat
class LiveSharer {
  final String userId;
  String name;
  String? profilePic;
  LatLng position;
  bool isLive;
  int? liveUntil;
  int? updatedAt;
  final bool isMe;

  LiveSharer({
    required this.userId,
    required this.name,
    this.profilePic,
    required this.position,
    required this.isLive,
    this.liveUntil,
    this.updatedAt,
    required this.isMe,
  });

  bool get isActuallyLive {
    if (!isLive) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return liveUntil == null || liveUntil! > now;
  }
}

class LiveLocationScreen extends StatefulWidget {
  final String? messageId;
  final String? currentUserId;
  final String? receiverId;
  final String? sharerId;
  final String? sharerName;
  final String? sharerProfilePic;
  final double initialLatitude;
  final double initialLongitude;
  final bool isLive;
  final int? liveUntil;
  final int? updatedAt;
  final bool isMe;

  const LiveLocationScreen({
    super.key,
    this.messageId,
    this.currentUserId,
    this.receiverId,
    this.sharerId,
    this.sharerName,
    this.sharerProfilePic,
    required this.initialLatitude,
    required this.initialLongitude,
    this.isLive = true,
    this.liveUntil,
    this.updatedAt,
    this.isMe = false,
  });

  @override
  State<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends State<LiveLocationScreen>
    with TickerProviderStateMixin {
  late final MapController _mapController;
  late final AnimationController _pulseController;

  // Active sharers in this chat (keyed by userId)
  final Map<String, LiveSharer> _liveSharers = {};
  final Map<String, UserModel> _userCache = {};

  LatLng? _myPosition;
  String? _addressText;
  bool _isFetchingAddress = false;
  bool _isMapReady = false;

  bool _autoFollow = true;
  MapTileTheme _currentTheme = MapTileTheme.osmDark;

  StreamSubscription? _allLiveMessagesSub;
  StreamSubscription<Position>? _myLocationSubscription;
  Timer? _countdownTimer;

  // In-app directions route state
  bool _showDirections = false;
  bool _isLoadingRoute = false;
  List<LatLng> _routePoints = [];
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;

  List<LiveSharer> get _activeSharers {
    if (_liveSharers.isEmpty) return [];
    final live = _liveSharers.values.where((s) => s.isActuallyLive).toList();
    if (live.isNotEmpty) return live;
    return _liveSharers.values.toList();
  }

  bool get _bothUsersSharing => _activeSharers.length >= 2;

  LiveSharer? get _primarySharer {
    final targetId = widget.sharerId ?? (widget.isMe ? widget.currentUserId : widget.receiverId);
    if (targetId != null && _liveSharers.containsKey(targetId)) {
      return _liveSharers[targetId];
    }
    return _liveSharers.isNotEmpty ? _liveSharers.values.first : null;
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();

    _countdownTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });

    // Seed initial sharer
    final currentUid = widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    final initialSharerId = widget.sharerId ?? (widget.isMe ? currentUid : widget.receiverId ?? 'initial');
    final initialPos = LatLng(widget.initialLatitude, widget.initialLongitude);

    _liveSharers[initialSharerId] = LiveSharer(
      userId: initialSharerId,
      name: widget.sharerName ?? (widget.isMe ? 'You' : 'Live Location'),
      profilePic: widget.sharerProfilePic,
      position: initialPos,
      isLive: widget.isLive,
      liveUntil: widget.liveUntil,
      updatedAt: widget.updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      isMe: widget.isMe || initialSharerId == currentUid,
    );

    _listenToChatLiveMessages();
    _initViewerLocation();
    _fetchAddress(widget.initialLatitude, widget.initialLongitude);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _countdownTimer?.cancel();
    _allLiveMessagesSub?.cancel();
    _myLocationSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Listen to all live_location messages in this chat from Firestore
  void _listenToChatLiveMessages() {
    final effectiveCurrentUser = widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
    final effectiveReceiver = widget.receiverId;

    if (effectiveCurrentUser == null || effectiveReceiver == null) return;

    try {
      _allLiveMessagesSub = FirebaseFirestore.instance
          .collection('users')
          .doc(effectiveCurrentUser)
          .collection('chats')
          .doc(effectiveReceiver)
          .collection('messages')
          .where('messageType', isEqualTo: 'live_location')
          .snapshots()
          .listen(
        (snapshot) {
          if (!mounted) return;
          _processLiveMessages(snapshot.docs, effectiveCurrentUser);
        },
        onError: (e) {
          log('Error listening to chat live messages: $e');
        },
      );
    } catch (e) {
      log('Error creating live location stream: $e');
    }
  }

  /// Process live messages from Firestore and update multi-user state
  void _processLiveMessages(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String currentUserId,
  ) {
    bool hasChanges = false;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final doc in docs) {
      final data = doc.data();
      final raw = data['fileMessageData'] as String?;
      if (raw == null || raw.isEmpty) continue;

      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final lat = (map['latitude'] as num?)?.toDouble();
        final lng = (map['longitude'] as num?)?.toDouble();
        final isLive = map['isLive'] == true;
        final liveUntil = (map['liveUntil'] as num?)?.toInt();
        final updatedAt = (map['updatedAt'] as num?)?.toInt();
        final senderId = (data['senderId'] as String?) ?? (map['sharerId'] as String?) ?? doc.id;
        final isMe = senderId == currentUserId;

        if (lat == null || lng == null) continue;

        final newPos = LatLng(lat, lng);

        if (_liveSharers.containsKey(senderId)) {
          final existing = _liveSharers[senderId]!;
          if (existing.position.latitude != newPos.latitude ||
              existing.position.longitude != newPos.longitude ||
              existing.isLive != isLive ||
              existing.liveUntil != liveUntil) {
            existing.position = newPos;
            existing.isLive = isLive;
            existing.liveUntil = liveUntil;
            existing.updatedAt = updatedAt ?? now;
            hasChanges = true;
          }
        } else {
          // New active sharer discovered
          _liveSharers[senderId] = LiveSharer(
            userId: senderId,
            name: isMe ? 'You' : 'Live User',
            profilePic: null,
            position: newPos,
            isLive: isLive,
            liveUntil: liveUntil,
            updatedAt: updatedAt ?? now,
            isMe: isMe,
          );
          hasChanges = true;
          _fetchUserProfile(senderId);
        }
      } catch (e) {
        log('Error parsing live location message doc: $e');
      }
    }

    if (hasChanges && mounted) {
      setState(() {});
      if (_showDirections) {
        _recalculateDirectionsIfActive();
      }
      if (_autoFollow && _activeSharers.length == 1 && _isMapReady) {
        try {
          _animatedMapMove(_activeSharers.first.position, _mapController.camera.zoom);
        } catch (_) {}
      }
    }
  }

  /// Fetch user profile details (name, profile picture) from cache or Firestore
  Future<void> _fetchUserProfile(String uid) async {
    if (_userCache.containsKey(uid)) {
      final user = _userCache[uid]!;
      if (mounted && _liveSharers.containsKey(uid)) {
        setState(() {
          final s = _liveSharers[uid]!;
          if (!s.isMe) s.name = user.name ?? 'User';
          s.profilePic = user.profilePic;
        });
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (mounted && doc.exists && doc.data() != null) {
        final user = UserModel.fromMap(doc.data()!);
        _userCache[uid] = user;
        if (_liveSharers.containsKey(uid)) {
          setState(() {
            final s = _liveSharers[uid]!;
            if (!s.isMe) s.name = user.name ?? 'User';
            s.profilePic = user.profilePic;
          });
        }
      }
    } catch (e) {
      log('Error fetching user profile for $uid: $e');
    }
  }

  /// Initialize viewer's real-time GPS location and track position
  Future<void> _initViewerLocation() async {
    try {
      final hasPerm = await LocationService.instance.checkAndRequestPermission();
      if (!hasPerm) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        final myLatLng = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _myPosition = myLatLng;
          final currentUid = widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
          if (currentUid != null && _liveSharers.containsKey(currentUid)) {
            _liveSharers[currentUid]!.position = myLatLng;
          }
        });
      }

      _myLocationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 8,
        ),
      ).listen((p) {
        if (mounted) {
          final myLatLng = LatLng(p.latitude, p.longitude);
          setState(() {
            _myPosition = myLatLng;
            final currentUid = widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
            if (currentUid != null && _liveSharers.containsKey(currentUid)) {
              _liveSharers[currentUid]!.position = myLatLng;
            }
          });
          if (_showDirections) {
            _recalculateDirectionsIfActive();
          }
        }
      });
    } catch (e) {
      log('Error initializing viewer location: $e');
    }
  }

  /// Reverse geocode coordinates to street address via Nominatim
  Future<void> _fetchAddress(double lat, double lng) async {
    if (_isFetchingAddress) return;
    _isFetchingAddress = true;

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          headers: {'User-Agent': 'worship_chat_mobile_app'},
        ),
      );

      final response = await dio.get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'format': 'json',
          'lat': lat,
          'lon': lng,
          'zoom': 18,
          'addressdetails': 1,
        },
      );

      if (mounted && response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final displayName = data['display_name'] as String?;
        final addr = data['address'] as Map<String, dynamic>?;

        String? compactAddress;
        if (addr != null) {
          final road = addr['road'] ?? addr['suburb'] ?? addr['neighbourhood'];
          final city = addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['county'];
          final state = addr['state'];
          if (road != null && city != null) {
            compactAddress = '$road, $city${state != null ? ', $state' : ''}';
          }
        }

        setState(() {
          _addressText = compactAddress ?? displayName;
          _isFetchingAddress = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isFetchingAddress = false);
    }
  }

  /// Smoothly animate the map camera to a target point
  void _animatedMapMove(LatLng destLocation, double destZoom) {
    if (!_isMapReady) return;
    try {
      final camera = _mapController.camera;
      final latTween = Tween<double>(begin: camera.center.latitude, end: destLocation.latitude);
      final lngTween = Tween<double>(begin: camera.center.longitude, end: destLocation.longitude);
      final zoomTween = Tween<double>(begin: camera.zoom, end: destZoom);

      final controller = AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      );

      final animation = CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic);

      controller.addListener(() {
        if (!_isMapReady) return;
        try {
          _mapController.move(
            LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
            zoomTween.evaluate(animation),
          );
        } catch (_) {}
      });

      animation.addStatusListener((status) {
        if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
          controller.dispose();
        }
      });

      controller.forward();
    } catch (_) {}
  }

  /// Fit camera to include all active sharers on screen simultaneously
  void _fitAllSharers() {
    if (!_isMapReady) return;
    try {
      final active = _activeSharers;
      if (active.isEmpty) return;

      if (active.length == 1) {
        _animatedMapMove(active.first.position, 16.5);
        return;
      }

      final points = active.map((s) => s.position).toList();
      final bounds = LatLngBounds.fromPoints(points);

      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.only(top: 130, bottom: 250, left: 55, right: 55),
          maxZoom: 17.5,
        ),
      );
    } catch (_) {}
  }

  /// In-app directions route fetching between 2 active live sharers
  Future<void> _fetchInAppRoute() async {
    final active = _activeSharers;
    if (active.length < 2) return;

    HapticFeedback.lightImpact();

    // Prefer "You" as start point and the other sharer as end point
    LiveSharer startSharer = active.firstWhere((s) => s.isMe, orElse: () => active[0]);
    LiveSharer endSharer = active.firstWhere((s) => !s.isMe, orElse: () => active[1]);

    final start = startSharer.position;
    final end = endSharer.position;

    setState(() => _isLoadingRoute = true);

    try {
      final url =
          'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      final response = await dio.get(url);
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final firstRoute = routes[0] as Map<String, dynamic>;
          final geometry = firstRoute['geometry'] as Map<String, dynamic>?;
          final coords = geometry?['coordinates'] as List?;
          final distance = (firstRoute['distance'] as num?)?.toDouble() ?? 0.0;
          final duration = (firstRoute['duration'] as num?)?.toDouble() ?? 0.0;

          if (coords != null && coords.isNotEmpty) {
            final points = coords.map((c) {
              final list = c as List;
              return LatLng((list[1] as num).toDouble(), (list[0] as num).toDouble());
            }).toList();

            if (mounted) {
              setState(() {
                _routePoints = points;
                _routeDistanceMeters = distance;
                _routeDurationSeconds = duration;
                _showDirections = true;
                _isLoadingRoute = false;
              });
              _fitRouteBounds(points);
              return;
            }
          }
        }
      }
    } catch (e) {
      log('OSRM routing failed, using direct geodesic line: $e');
    }

    // Fallback: Direct geodesic polyline between both users
    final directDistance = const Distance().as(LengthUnit.Meter, start, end);
    final approxSeconds = (directDistance / (35000 / 3600)).roundToDouble();

    if (mounted) {
      setState(() {
        _routePoints = [start, end];
        _routeDistanceMeters = directDistance;
        _routeDurationSeconds = approxSeconds;
        _showDirections = true;
        _isLoadingRoute = false;
      });
      _fitRouteBounds([start, end]);
    }
  }

  void _recalculateDirectionsIfActive() {
    if (!_showDirections || _activeSharers.length < 2) return;
    final active = _activeSharers;
    LiveSharer startSharer = active.firstWhere((s) => s.isMe, orElse: () => active[0]);
    LiveSharer endSharer = active.firstWhere((s) => !s.isMe, orElse: () => active[1]);
    final directDistance = const Distance().as(LengthUnit.Meter, startSharer.position, endSharer.position);
    _routeDistanceMeters = directDistance;
  }

  void _fitRouteBounds(List<LatLng> points) {
    if (!_isMapReady || points.isEmpty) return;
    try {
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.only(top: 140, bottom: 270, left: 55, right: 55),
          maxZoom: 17.0,
        ),
      );
    } catch (_) {}
  }

  /// Stop live location sharing
  Future<void> _handleStopSharing() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1C2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Stop Sharing Location?', style: TextStyle(color: Colors.white, fontSize: 17)),
        content: const Text(
          'Live location sharing will end for this chat immediately.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop Sharing', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    HapticFeedback.mediumImpact();
    final effectiveCurrentUser = widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
    final effectiveReceiver = widget.receiverId;

    if (widget.messageId != null && effectiveCurrentUser != null && effectiveReceiver != null) {
      await LocationService.instance.stopLiveLocationSharing(
        messageId: widget.messageId!,
        currentUserId: effectiveCurrentUser,
        receiverId: effectiveReceiver,
      );
      if (mounted) {
        setState(() {
          if (_liveSharers.containsKey(effectiveCurrentUser)) {
            _liveSharers[effectiveCurrentUser]!.isLive = false;
          }
          if (_showDirections) _showDirections = false;
        });
      }
    }
  }

  /// Copy coordinates to clipboard
  void _copyCoordinates() {
    final target = _primarySharer?.position ?? LatLng(widget.initialLatitude, widget.initialLongitude);
    Clipboard.setData(ClipboardData(
      text: '${target.latitude.toStringAsFixed(6)}, ${target.longitude.toStringAsFixed(6)}',
    ));
    HapticFeedback.selectionClick();
    AppSnackBar.success(context, 'Coordinates copied to clipboard');
  }

  String _getTileUrl() {
    switch (_currentTheme) {
      case MapTileTheme.osmDark:
      case MapTileTheme.openStreetMap:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapTileTheme.osmHumanitarian:
        return 'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png';
      case MapTileTheme.cyclosm:
        return 'https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png';
      case MapTileTheme.esriDark:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}';
      case MapTileTheme.esriSatellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }
  }

  String _formatLiveTimeRemaining(LiveSharer sharer) {
    if (!sharer.isActuallyLive) return 'Live ended';
    if (sharer.liveUntil == null) return 'Live active';

    final now = DateTime.now().millisecondsSinceEpoch;
    final diffMs = sharer.liveUntil! - now;
    if (diffMs <= 0) return 'Live ended';

    final totalMin = (diffMs / 60000).ceil();
    final endTimeStr = DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(sharer.liveUntil!));

    if (totalMin > 60) {
      final hours = totalMin ~/ 60;
      final mins = totalMin % 60;
      return '$endTimeStr (${hours}h ${mins}m left)';
    } else {
      return '$endTimeStr ($totalMin min left)';
    }
  }

  String _formatDistanceBetweenSharers() {
    final active = _activeSharers;
    if (active.length < 2) return '';
    final meters = const Distance().as(LengthUnit.Meter, active[0].position, active[1].position);
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m apart';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km apart';
  }

  String _formatRouteDistance() {
    if (_routeDistanceMeters == null) return '';
    if (_routeDistanceMeters! < 1000) {
      return '${_routeDistanceMeters!.toStringAsFixed(0)} m';
    }
    return '${(_routeDistanceMeters! / 1000).toStringAsFixed(1)} km';
  }

  String _formatRouteDuration() {
    if (_routeDurationSeconds == null) return '';
    final mins = (_routeDurationSeconds! / 60).round();
    if (mins < 1) return '~1 min';
    if (mins > 60) {
      return '~${mins ~/ 60}h ${mins % 60}m';
    }
    return '~$mins mins';
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeSharers;
    final centerPos = active.isNotEmpty
        ? active.first.position
        : LatLng(widget.initialLatitude, widget.initialLongitude);

    final currentUid = widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
    final isMeSharing = currentUid != null &&
        _liveSharers.containsKey(currentUid) &&
        _liveSharers[currentUid]!.isActuallyLive;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Stack(
        children: [
          // ── FlutterMap with Rich Tiles, Polylines, Circles & Markers ──────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: centerPos,
              initialZoom: 16.2,
              minZoom: 3.0,
              maxZoom: 18.5,
              onMapReady: () {
                if (mounted) {
                  setState(() => _isMapReady = true);
                  _fitAllSharers();
                }
              },
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture && _autoFollow) {
                  setState(() => _autoFollow = false);
                }
              },
            ),
            children: [
              // Tile Layer (100% Free Open-Source OSM Tiles, No API Key Required)
              TileLayer(
                urlTemplate: _getTileUrl(),
                userAgentPackageName: 'com.shadow.worshipchat',
                maxZoom: 19,
                tileBuilder: (context, tileWidget, tile) {
                  if (_currentTheme == MapTileTheme.osmDark) {
                    return ColorFiltered(
                      colorFilter: const ColorFilter.matrix(<double>[
                        -0.80, 0,     0,     0, 245,
                        0,     -0.80, 0,     0, 245,
                        0,     0,     -0.78, 0, 250,
                        0,     0,     0,     1, 0,
                      ]),
                      child: tileWidget,
                    );
                  }
                  return tileWidget;
                },
              ),

              // Directions In-App Polyline Layer
              if (_showDirections && _routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    // Outer glowing route outline
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 8.0,
                      color: tabColor.withValues(alpha: 0.35),
                      strokeCap: StrokeCap.round,
                      strokeJoin: StrokeJoin.round,
                    ),
                    // Inner vibrant route line
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 4.5,
                      color: tabColor,
                      strokeCap: StrokeCap.round,
                      strokeJoin: StrokeJoin.round,
                    ),
                  ],
                ),

              // Sharer Accuracy / Radar Wave Circles
              CircleLayer(
                circles: [
                  ...active.map((sharer) {
                    final color = sharer.isMe ? const Color(0xFF29B6F6) : const Color(0xFF00E676);
                    return CircleMarker(
                      point: sharer.position,
                      radius: sharer.isActuallyLive ? 46 : 24,
                      color: color.withValues(alpha: 0.12),
                      borderColor: color.withValues(alpha: 0.38),
                      borderStrokeWidth: 1.5,
                    );
                  }),
                  if (_myPosition != null && !isMeSharing)
                    CircleMarker(
                      point: _myPosition!,
                      radius: 20,
                      color: const Color(0xFF29B6F6).withValues(alpha: 0.15),
                      borderColor: const Color(0xFF29B6F6).withValues(alpha: 0.4),
                      borderStrokeWidth: 1.2,
                    ),
                ],
              ),

              // Multi-User Live Markers Layer (Both Users Shown Together)
              MarkerLayer(
                markers: [
                  ...active.map((sharer) {
                    return Marker(
                      point: sharer.position,
                      width: 78,
                      height: 96,
                      alignment: Alignment.topCenter,
                      child: _buildUserPinMarker(sharer),
                    );
                  }),
                  if (_myPosition != null && !isMeSharing)
                    Marker(
                      point: _myPosition!,
                      width: 28,
                      height: 28,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1E88E5),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1E88E5).withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // ── Top Glass App Bar ─────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: _buildTopGlassBar(),
            ),
          ),

          // ── Floating Action Controls (Right side) ─────────────────────────
          Positioned(
            right: 14,
            top: 130,
            child: _buildFloatingControls(),
          ),

          // ── Directions Route Floating Banner ──────────────────────────────
          if (_showDirections && _routeDistanceMeters != null)
            Positioned(
              left: 14,
              right: 14,
              bottom: 236,
              child: _buildDirectionsBanner(),
            ),

          // ── Bottom Sheet Information Panel (WhatsApp Style) ───────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomCard(isMeSharing),
          ),
        ],
      ),
    );
  }

  /// Open interactive Map Themes & Layers bottom sheet (100% Free Open-Source, Zero API Keys)
  void _openMapThemeSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF161524).withValues(alpha: 0.96),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 28,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 38,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: tabColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.layers_rounded, color: tabColor, size: 20),
                              ),
                              const SizedBox(width: 10),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Map Styles & Layers',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'OpenStreetMap • Zero API keys',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // 6 Map Style cards in 2-column grid
                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 2.1,
                            children: [
                              _buildThemeCard(
                                theme: MapTileTheme.osmDark,
                                title: 'OSM Dark Luxury',
                                subtitle: 'Midnight Dark',
                                icon: Icons.dark_mode_rounded,
                                accentColor: const Color(0xFF00E5FF),
                                onSelect: (t) {
                                  setState(() => _currentTheme = t);
                                  Navigator.pop(ctx);
                                },
                              ),
                              _buildThemeCard(
                                theme: MapTileTheme.esriDark,
                                title: 'Esri Dark Canvas',
                                subtitle: 'Ultra-Minimalist',
                                icon: Icons.nightlight_round,
                                accentColor: const Color(0xFF90CAF9),
                                onSelect: (t) {
                                  setState(() => _currentTheme = t);
                                  Navigator.pop(ctx);
                                },
                              ),
                              _buildThemeCard(
                                theme: MapTileTheme.osmHumanitarian,
                                title: 'Humanitarian HOT',
                                subtitle: 'Warm Pastels',
                                icon: Icons.wb_sunny_rounded,
                                accentColor: const Color(0xFFFFB300),
                                onSelect: (t) {
                                  setState(() => _currentTheme = t);
                                  Navigator.pop(ctx);
                                },
                              ),
                              _buildThemeCard(
                                theme: MapTileTheme.cyclosm,
                                title: 'CyclOSM Urban',
                                subtitle: 'Streets & Paths',
                                icon: Icons.directions_bike_rounded,
                                accentColor: const Color(0xFFAB47BC),
                                onSelect: (t) {
                                  setState(() => _currentTheme = t);
                                  Navigator.pop(ctx);
                                },
                              ),
                              _buildThemeCard(
                                theme: MapTileTheme.esriSatellite,
                                title: 'World Satellite',
                                subtitle: 'Photographic View',
                                icon: Icons.satellite_alt_rounded,
                                accentColor: const Color(0xFF26A69A),
                                onSelect: (t) {
                                  setState(() => _currentTheme = t);
                                  Navigator.pop(ctx);
                                },
                              ),
                              _buildThemeCard(
                                theme: MapTileTheme.openStreetMap,
                                title: 'OSM Standard',
                                subtitle: 'Classic Open Map',
                                icon: Icons.map_rounded,
                                accentColor: const Color(0xFF66BB6A),
                                onSelect: (t) {
                                  setState(() => _currentTheme = t);
                                  Navigator.pop(ctx);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildThemeCard({
    required MapTileTheme theme,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required ValueChanged<MapTileTheme> onSelect,
  }) {
    final isSelected = _currentTheme == theme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onSelect(theme);
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: 0.16)
                : const Color(0xFF1E1C2E).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? accentColor : Colors.white.withValues(alpha: 0.1),
              width: isSelected ? 1.6 : 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: isSelected ? 0.28 : 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: accentColor, size: 17),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isSelected ? accentColor : Colors.white54,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: accentColor, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// Top Glassmorphic Navigation Bar
  Widget _buildTopGlassBar() {
    final active = _activeSharers;
    final count = active.length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF161524).withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Back',
              ),
              const SizedBox(width: 4),

              // Avatars (Single or Multi-user cluster)
              _buildTopBarAvatars(active),
              const SizedBox(width: 10),

              // Title & Live Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      !widget.isLive
                          ? (widget.sharerName != null ? '${widget.sharerName}\'s Location' : 'Shared Location')
                          : count >= 2
                              ? 'Live Location ($count sharing)'
                              : (active.isNotEmpty ? active.first.name : 'Live Location'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: !widget.isLive ? const Color(0xFFFFB300) : const Color(0xFF00E676),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            !widget.isLive
                                ? 'Location Pin'
                                : count >= 2
                                    ? _formatDistanceBetweenSharers()
                                    : (active.isNotEmpty ? _formatLiveTimeRemaining(active.first) : 'Active'),
                            style: TextStyle(
                              color: !widget.isLive ? Colors.white70 : const Color(0xFF00E676),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Directions Toggle in AppBar (Only if both sharing)
              if (_bothUsersSharing)
                IconButton(
                  icon: Icon(
                    _showDirections ? Icons.directions_off_rounded : Icons.directions_rounded,
                    color: tabColor,
                    size: 22,
                  ),
                  tooltip: _showDirections ? 'Hide Directions' : 'In-App Directions',
                  onPressed: () {
                    if (_showDirections) {
                      setState(() => _showDirections = false);
                    } else {
                      _fetchInAppRoute();
                    }
                  },
                ),

              // Map Styles & Layers Modal Button
              IconButton(
                icon: const Icon(Icons.layers_rounded, color: Colors.white, size: 22),
                tooltip: 'Map Styles & Layers',
                onPressed: _openMapThemeSheet,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Avatars cluster in top bar
  Widget _buildTopBarAvatars(List<LiveSharer> active) {
    if (active.length <= 1) {
      final s = active.isNotEmpty ? active.first : null;
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF00E676), width: 2),
        ),
        child: ClipOval(
          child: (s?.profilePic != null && s!.profilePic!.isNotEmpty)
              ? CachedNetworkImage(
                  imageUrl: s.profilePic!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const Icon(Icons.person, color: Colors.white54),
                  errorWidget: (_, __, ___) => const Icon(Icons.person, color: Colors.white54),
                )
              : const Icon(Icons.person, color: Colors.white54, size: 22),
        ),
      );
    }

    // Two users overlapping avatars (WhatsApp style)
    return SizedBox(
      width: 48,
      height: 38,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: _buildMiniAvatarCircle(active[0], const Color(0xFF29B6F6)),
          ),
          Positioned(
            right: 0,
            child: _buildMiniAvatarCircle(active[1], const Color(0xFF00E676)),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniAvatarCircle(LiveSharer s, Color borderColor) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
        color: const Color(0xFF161524),
      ),
      child: ClipOval(
        child: (s.profilePic != null && s.profilePic!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: s.profilePic!,
                fit: BoxFit.cover,
                placeholder: (_, __) => const Icon(Icons.person, color: Colors.white54, size: 16),
                errorWidget: (_, __, ___) => const Icon(Icons.person, color: Colors.white54, size: 16),
              )
            : const Icon(Icons.person, color: Colors.white54, size: 16),
      ),
    );
  }

  /// User Live Pin Marker on Map (Radar pulse + Avatar + Pin Pointer + Name Pill)
  Widget _buildUserPinMarker(LiveSharer sharer) {
    final isActuallyLive = sharer.isActuallyLive;
    final ringColor = sharer.isMe ? const Color(0xFF29B6F6) : const Color(0xFF00E676);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing live radar wave
            if (isActuallyLive)
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final scale = 1.0 + (_pulseController.value * 0.45);
                  final opacity = (1.0 - _pulseController.value).clamp(0.0, 1.0);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ringColor.withValues(alpha: 0.3 * opacity),
                      ),
                    ),
                  );
                },
              ),

            // Profile Avatar inside circular pin
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1E1C2E),
                border: Border.all(
                  color: isActuallyLive ? ringColor : Colors.grey,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isActuallyLive
                        ? ringColor.withValues(alpha: 0.5)
                        : Colors.black.withValues(alpha: 0.4),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipOval(
                child: (sharer.profilePic != null && sharer.profilePic!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: sharer.profilePic!,
                        fit: BoxFit.cover,
                        placeholder: (ctx, url) =>
                            const Icon(Icons.person, color: Colors.white, size: 26),
                        errorWidget: (ctx, url, error) =>
                            const Icon(Icons.person, color: Colors.white, size: 26),
                      )
                    : Center(
                        child: Text(
                          sharer.name.isNotEmpty ? sharer.name[0].toUpperCase() : 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),

        // Pin pointer tip
        CustomPaint(
          size: const Size(14, 8),
          painter: _PinTipPainter(
            color: isActuallyLive ? ringColor : Colors.grey[600]!,
          ),
        ),

        const SizedBox(height: 2),

        // Name tag pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActuallyLive ? ringColor.withValues(alpha: 0.5) : Colors.white12,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActuallyLive)
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: ringColor,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                sharer.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Floating control action buttons on right side
  Widget _buildFloatingControls() {
    double rotation = 0.0;
    if (_isMapReady) {
      try {
        rotation = _mapController.camera.rotation;
      } catch (_) {}
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Map Layers / Styles Modal Button
        _buildFabButton(
          icon: const Icon(Icons.layers_rounded, color: tabColor, size: 20),
          tooltip: 'Map Styles & Layers',
          borderColor: tabColor.withValues(alpha: 0.35),
          onTap: _openMapThemeSheet,
        ),
        const SizedBox(height: 10),

        // Fit All Sharers Button
        _buildFabButton(
          icon: const Icon(Icons.all_out_rounded, color: Color(0xFF00E676), size: 20),
          tooltip: 'Fit All Sharers',
          onTap: () {
            HapticFeedback.lightImpact();
            _fitAllSharers();
          },
        ),
        const SizedBox(height: 10),

        // Compass / North Reset Button
        _buildFabButton(
          icon: Transform.rotate(
            angle: (rotation * (math.pi / 180)),
            child: const Icon(Icons.explore_rounded, color: Color(0xFFFFB300), size: 20),
          ),
          tooltip: 'Reset North',
          onTap: () {
            if (!_isMapReady) return;
            HapticFeedback.lightImpact();
            try {
              _mapController.rotate(0.0);
            } catch (_) {}
          },
        ),
        const SizedBox(height: 10),

        // Re-center on live location / Auto Follow
        _buildFabButton(
          icon: Icon(
            Icons.radar_rounded,
            color: _autoFollow ? const Color(0xFF00E676) : Colors.white,
            size: 20,
          ),
          borderColor: _autoFollow ? const Color(0xFF00E676).withValues(alpha: 0.6) : null,
          tooltip: 'Auto Follow',
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _autoFollow = true);
            final target = _primarySharer?.position ?? LatLng(widget.initialLatitude, widget.initialLongitude);
            _animatedMapMove(target, 16.5);
          },
        ),
        const SizedBox(height: 10),

        // Center on My Location (GPS)
        if (_myPosition != null) ...[
          _buildFabButton(
            icon: const Icon(Icons.my_location_rounded, color: Color(0xFF29B6F6), size: 20),
            tooltip: 'My GPS Location',
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _autoFollow = false);
              _animatedMapMove(_myPosition!, 16.5);
            },
          ),
          const SizedBox(height: 10),
        ],

        // Zoom In
        _buildFabButton(
          icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
          tooltip: 'Zoom In',
          onTap: () {
            if (!_isMapReady) return;
            try {
              final z = (_mapController.camera.zoom + 1).clamp(3.0, 18.5);
              _animatedMapMove(_mapController.camera.center, z);
            } catch (_) {}
          },
        ),
        const SizedBox(height: 8),

        // Zoom Out
        _buildFabButton(
          icon: const Icon(Icons.remove_rounded, color: Colors.white, size: 20),
          tooltip: 'Zoom Out',
          onTap: () {
            if (!_isMapReady) return;
            try {
              final z = (_mapController.camera.zoom - 1).clamp(3.0, 18.5);
              _animatedMapMove(_mapController.camera.center, z);
            } catch (_) {}
          },
        ),
      ],
    );
  }

  Widget _buildFabButton({
    required Widget icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? backgroundColor,
    Color? borderColor,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: backgroundColor ?? const Color(0xFF161524).withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: borderColor ?? Colors.white.withValues(alpha: 0.14),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: onTap,
              child: Center(child: icon),
            ),
          ),
        ),
      ),
    );
  }

  /// In-App Directions Info Floating Banner
  Widget _buildDirectionsBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF161524).withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tabColor.withValues(alpha: 0.45), width: 1),
            boxShadow: [
              BoxShadow(
                color: tabColor.withValues(alpha: 0.25),
                blurRadius: 18,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tabColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.navigation_rounded, color: tabColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          _formatRouteDuration(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '• ${_formatRouteDistance()}',
                          style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Fastest route on OpenStreetMap',
                      style: TextStyle(color: Colors.white60, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                tooltip: 'Clear Directions',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() => _showDirections = false);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom Sheet Information Panel (Rich WhatsApp Style)
  Widget _buildBottomCard(bool isMeSharing) {
    final active = _activeSharers;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161524).withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top drag pill
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Active Sharers List
                  if (active.length > 1) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ACTIVE LIVE SHARERS',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          _formatDistanceBetweenSharers(),
                          style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: active.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, idx) {
                          final s = active[idx];
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1C2E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: s.isMe ? const Color(0xFF29B6F6) : const Color(0xFF00E676),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundImage: (s.profilePic != null && s.profilePic!.isNotEmpty)
                                      ? CachedNetworkImageProvider(s.profilePic!)
                                      : null,
                                  child: (s.profilePic == null || s.profilePic!.isEmpty)
                                      ? Text(s.name.isNotEmpty ? s.name[0] : 'U', style: const TextStyle(fontSize: 11))
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      s.name,
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      _formatLiveTimeRemaining(s),
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Address Tile
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1C2E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined, color: tabColor, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _addressText ??
                                '${_primarySharer?.position.latitude.toStringAsFixed(5) ?? widget.initialLatitude.toStringAsFixed(5)}, ${_primarySharer?.position.longitude.toStringAsFixed(5) ?? widget.initialLongitude.toStringAsFixed(5)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, color: Colors.white54, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Copy coordinates',
                          onPressed: _copyCoordinates,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Action Buttons Row (Directions & Stop Sharing)
                  Row(
                    children: [
                      // Stop Sharing Button (if current user is sharing)
                      if (isMeSharing) ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.stop_circle_outlined, size: 18, color: Colors.white),
                            label: const Text(
                              'Stop Sharing',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF5252),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            onPressed: _handleStopSharing,
                          ),
                        ),
                        if (_bothUsersSharing) const SizedBox(width: 10),
                      ],

                      // "Get Directions" ONLY if both users are sharing live location
                      if (_bothUsersSharing)
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: _isLoadingRoute
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : Icon(
                                    _showDirections ? Icons.directions_off_rounded : Icons.navigation_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                            label: Text(
                              _showDirections ? 'Hide Route' : 'Get Directions',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: tabColor,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            onPressed: () {
                              if (_showDirections) {
                                setState(() => _showDirections = false);
                              } else {
                                _fetchInAppRoute();
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for the downward pin pointer tip
class _PinTipPainter extends CustomPainter {
  final Color color;
  const _PinTipPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PinTipPainter oldDelegate) => oldDelegate.color != color;
}
