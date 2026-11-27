import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:worship_chat/common/utils/location_service.dart';
import 'package:worship_chat/common/utils/map_style_config.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/models/user_model.dart';

/// Represents an active participant sharing live location in this chat.
class LiveSharer {
  final String userId;
  String name;
  String? profilePic;
  LatLng position;
  LatLng animatedPosition;
  bool isLive;
  int? liveUntil;
  int? updatedAt;
  double? heading;
  double? speed;
  double? accuracy;
  final bool isMe;

  LiveSharer({
    required this.userId,
    required this.name,
    this.profilePic,
    required this.position,
    LatLng? animatedPosition,
    required this.isLive,
    this.liveUntil,
    this.updatedAt,
    this.heading,
    this.speed,
    this.accuracy,
    required this.isMe,
  }) : animatedPosition = animatedPosition ?? position;

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
  final String? initialPlaceName;
  final String? initialAddress;
  final double? initialAccuracy;
  final double? initialHeading;
  final double? initialSpeed;

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
    this.initialPlaceName,
    this.initialAddress,
    this.initialAccuracy,
    this.initialHeading,
    this.initialSpeed,
  });

  /// Selects at most one authoritative [LiveSharer] per `senderId`, always
  /// preferring an active `isLive` message (and matching `preferredMessageId`),
  /// or falling back to the most recently updated entry when all have ended.
  @visibleForTesting
  static Map<String, LiveSharer> selectLatestSharersFromPayloads(
    List<Map<String, dynamic>> rawEntries, {
    required String currentUserId,
    String? preferredMessageId,
    int? nowMs,
  }) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final bestBySender = <String, ({LiveSharer sharer, bool isPreferred, int sortTs})>{};

    for (final entry in rawEntries) {
      final raw = entry['fileMessageData'] as String?;
      if (raw == null || raw.isEmpty) continue;
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final lat = (map['latitude'] as num?)?.toDouble();
        final lng = (map['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final isLive = map['isLive'] == true;
        final liveUntil = (map['liveUntil'] as num?)?.toInt();
        final updatedAt = (map['updatedAt'] as num?)?.toInt();
        final timeSent = (entry['timeSent'] as num?)?.toInt();
        final msgId = entry['messageId']?.toString() ?? '';
        final senderId =
            (entry['senderId'] as String?) ??
            (map['sharerId'] as String?) ??
            msgId;
        if (senderId.isEmpty) continue;

        final isMe = senderId == currentUserId;
        final isPreferred =
            preferredMessageId != null && msgId == preferredMessageId;
        final sortTs = updatedAt ?? timeSent ?? 0;

        final sharer = LiveSharer(
          userId: senderId,
          name: isMe ? 'You' : 'Live User',
          position: LatLng(lat, lng),
          isLive: isLive,
          liveUntil: liveUntil,
          updatedAt: updatedAt ?? timeSent,
          heading: (map['heading'] as num?)?.toDouble(),
          speed: (map['speed'] as num?)?.toDouble(),
          accuracy: (map['accuracy'] as num?)?.toDouble(),
          isMe: isMe,
        );
        final candidateActive =
            sharer.isLive && (liveUntil == null || liveUntil > now);

        final prev = bestBySender[senderId];
        if (prev == null) {
          bestBySender[senderId] = (
            sharer: sharer,
            isPreferred: isPreferred,
            sortTs: sortTs,
          );
          continue;
        }

        final prevActive = prev.sharer.isLive &&
            (prev.sharer.liveUntil == null || prev.sharer.liveUntil! > now);

        bool shouldReplace = false;
        if (candidateActive != prevActive) {
          shouldReplace = candidateActive;
        } else if (isPreferred != prev.isPreferred) {
          shouldReplace = isPreferred;
        } else if (sortTs >= prev.sortTs) {
          shouldReplace = true;
        }

        if (shouldReplace) {
          bestBySender[senderId] = (
            sharer: sharer,
            isPreferred: isPreferred,
            sortTs: sortTs,
          );
        }
      } catch (_) {}
    }

    return {
      for (final e in bestBySender.entries) e.key: e.value.sharer,
    };
  }

  @override
  State<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends State<LiveLocationScreen>
    with TickerProviderStateMixin {
  late final MapController _mapController;
  late final DraggableScrollableController _sheetController;
  late final AnimationController _pulseController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  final Map<String, LiveSharer> _liveSharers = {};
  final Map<String, List<LatLng>> _sharerTrails = {};
  final Map<String, AnimationController> _markerAnimControllers = {};
  final Map<String, UserModel> _userCache = {};

  AnimationController? _cameraAnimController;
  double _cameraRotationDeg = 0.0;

  String? _focusedSharerId;
  bool _autoFollow = true;
  bool _isMapReady = false;
  AppMapStyle _currentStyle = MapStyleRegistry.styleNotifier.value;

  // Viewer GPS
  LatLng? _myPosition;
  double _myAccuracy = 20.0;
  double? _myHeading;
  LocationReadiness _locationReadiness = LocationReadiness.ready;

  // Place & address metadata + dropped pin
  String? _placeName;
  String? _addressText;
  LatLng? _lastGeocodedPoint;
  CancelToken? _reverseCancel;
  PlaceSearchResult? _droppedPin;

  // Search overlay
  List<PlaceSearchResult> _searchResults = const [];
  bool _isSearching = false;
  Timer? _searchDebounce;
  CancelToken? _searchCancel;

  // Subscriptions & Timers
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _allLiveMessagesSub;
  StreamSubscription<Position>? _myLocationSubscription;
  Timer? _countdownTimer;

  // In-App Google-Maps-Style Navigation / Directions
  bool _showDirections = false;
  bool _isLoadingRoute = false;
  TravelMode _travelMode = TravelMode.driving;
  MapRouteResult? _activeRoute;
  LatLng? _lastRouteOrigin;
  int _lastRouteFetchedMs = 0;
  CancelToken? _routeCancel;

  List<LiveSharer> get _activeSharers {
    if (_liveSharers.isEmpty) return const [];
    final live = _liveSharers.values.where((s) => s.isActuallyLive).toList();
    if (live.isNotEmpty) return live;
    return _liveSharers.values.toList();
  }

  LiveSharer? get _focusedSharer {
    if (_focusedSharerId != null && _liveSharers.containsKey(_focusedSharerId)) {
      return _liveSharers[_focusedSharerId];
    }
    final targetId =
        widget.sharerId ?? (widget.isMe ? widget.currentUserId : widget.receiverId);
    if (targetId != null && _liveSharers.containsKey(targetId)) {
      return _liveSharers[targetId];
    }
    return _activeSharers.isNotEmpty
        ? _activeSharers.first
        : (_liveSharers.isNotEmpty ? _liveSharers.values.first : null);
  }

  bool get _bothUsersSharing => _activeSharers.length >= 2;

  LatLng? get _navigationDestination {
    if (_droppedPin != null) return _droppedPin!.latLng;
    final focused = _focusedSharer;
    if (focused != null && !focused.isMe) return focused.position;
    final other = _activeSharers.where((s) => !s.isMe);
    if (other.isNotEmpty) return other.first.position;
    return focused?.position ??
        LatLng(widget.initialLatitude, widget.initialLongitude);
  }

  bool get _canGetDirections {
    if (_droppedPin != null && _myPosition != null) return true;
    final dest = _navigationDestination;
    if (_myPosition != null && dest != null) {
      final d = const Distance().as(LengthUnit.Meter, _myPosition!, dest);
      if (d > 15) return true;
    }
    return _bothUsersSharing;
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _sheetController = DraggableScrollableController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();

    _countdownTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });

    _placeName = widget.initialPlaceName;
    _addressText = widget.initialAddress;

    final currentUid = _safeCurrentUid();
    final initialSharerId = widget.sharerId ??
        (widget.isMe ? currentUid : (widget.receiverId ?? 'initial'));
    final initialPos = LatLng(widget.initialLatitude, widget.initialLongitude);
    _focusedSharerId = initialSharerId;

    _liveSharers[initialSharerId] = LiveSharer(
      userId: initialSharerId,
      name: widget.sharerName ?? (widget.isMe ? 'You' : 'Shared Location'),
      profilePic: widget.sharerProfilePic,
      position: initialPos,
      isLive: widget.isLive,
      liveUntil: widget.liveUntil,
      updatedAt: widget.updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      heading: widget.initialHeading,
      speed: widget.initialSpeed,
      accuracy: widget.initialAccuracy,
      isMe: widget.isMe || (currentUid.isNotEmpty && initialSharerId == currentUid),
    );
    _sharerTrails[initialSharerId] = [initialPos];

    // Ensure LocationService is tracking if this user is actively sharing live.
    if (widget.isMe &&
        widget.isLive &&
        widget.messageId != null &&
        widget.receiverId != null &&
        currentUid.isNotEmpty &&
        (widget.liveUntil == null ||
            widget.liveUntil! > DateTime.now().millisecondsSinceEpoch)) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final remainingMs = (widget.liveUntil ?? (now + 3600000)) - now;
      if (remainingMs > 0 &&
          !LocationService.instance.isTracking(widget.messageId!)) {
        LocationService.instance.startLiveLocationTracking(
          messageId: widget.messageId!,
          currentUserId: currentUid,
          receiverId: widget.receiverId!,
          duration: Duration(milliseconds: remainingMs),
          explicitLiveUntil: widget.liveUntil,
        );
      }
    }

    _loadPreferredStyle();
    _listenToChatLiveMessages();
    _initViewerLocation();
    if (_addressText == null || _addressText!.isEmpty) {
      _reverseGeocodeTarget(initialPos);
    }
  }

  String _safeCurrentUid() {
    if (widget.currentUserId != null && widget.currentUserId!.isNotEmpty) {
      return widget.currentUserId!;
    }
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _loadPreferredStyle() async {
    final loaded = await MapStyleRegistry.loadSavedStyle();
    if (mounted) {
      setState(() => _currentStyle = loaded);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _cameraAnimController?.dispose();
    for (final ctrl in _markerAnimControllers.values) {
      ctrl.dispose();
    }
    _markerAnimControllers.clear();
    _countdownTimer?.cancel();
    _searchDebounce?.cancel();
    _searchCancel?.cancel();
    _reverseCancel?.cancel();
    _routeCancel?.cancel();
    _allLiveMessagesSub?.cancel();
    _myLocationSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _sheetController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _listenToChatLiveMessages() {
    final effectiveCurrentUser = _safeCurrentUid();
    final effectiveReceiver = widget.receiverId;
    if (effectiveCurrentUser.isEmpty || effectiveReceiver == null) return;

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

  void _processLiveMessages(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String currentUserId,
  ) {
    final rawEntries = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final data = doc.data();
      rawEntries.add({
        'messageId': doc.id,
        'senderId': data['senderId'],
        'fileMessageData': data['fileMessageData'],
        'timeSent': data['timeSent'],
      });
    }

    final selected = LiveLocationScreen.selectLatestSharersFromPayloads(
      rawEntries,
      currentUserId: currentUserId,
      preferredMessageId: widget.messageId,
    );

    bool hasChanges = false;
    final newlyMoving = <String, ({LatLng from, LatLng to})>{};

    for (final entry in selected.entries) {
      final senderId = entry.key;
      final latest = entry.value;
      final existing = _liveSharers[senderId];

      if (existing == null) {
        _liveSharers[senderId] = latest;
        _sharerTrails[senderId] = [latest.position];
        hasChanges = true;
        _fetchUserProfile(senderId);
      } else {
        final posChanged = existing.position.latitude != latest.position.latitude ||
            existing.position.longitude != latest.position.longitude;
        final metaChanged = existing.isLive != latest.isLive ||
            existing.liveUntil != latest.liveUntil ||
            existing.updatedAt != latest.updatedAt;

        if (posChanged) {
          newlyMoving[senderId] = (
            from: existing.animatedPosition,
            to: latest.position,
          );
          final trail = _sharerTrails.putIfAbsent(senderId, () => []);
          if (trail.isEmpty ||
              const Distance().as(
                    LengthUnit.Meter,
                    trail.last,
                    latest.position,
                  ) >=
                  5.0) {
            trail.add(latest.position);
            if (trail.length > 180) {
              trail.removeAt(0);
            }
          }
          existing.position = latest.position;
        }
        if (posChanged || metaChanged) {
          existing.isLive = latest.isLive;
          existing.liveUntil = latest.liveUntil;
          existing.updatedAt = latest.updatedAt;
          existing.heading = latest.heading ?? existing.heading;
          existing.speed = latest.speed ?? existing.speed;
          existing.accuracy = latest.accuracy ?? existing.accuracy;
          hasChanges = true;
        }
      }
    }

    if (!hasChanges || !mounted) return;

    for (final move in newlyMoving.entries) {
      _animateMarkerSlide(move.key, move.value.from, move.value.to);
    }

    setState(() {});

    final focused = _focusedSharer;
    if (focused != null && !focused.isMe) {
      _maybeRefreshFocusedAddress(focused.position);
    }
    if (_showDirections) {
      _maybeRefreshRouteForMovement();
    }
    if (_autoFollow && _isMapReady) {
      if (_bothUsersSharing && _focusedSharerId == null) {
        _fitAllTargets();
      } else if (focused != null) {
        _animatedMapMove(focused.position, _mapController.camera.zoom);
      }
    }
  }

  void _animateMarkerSlide(String userId, LatLng from, LatLng to) {
    _markerAnimControllers[userId]?.stop();
    _markerAnimControllers[userId]?.dispose();

    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _markerAnimControllers[userId] = ctrl;
    final curve = CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic);

    ctrl.addListener(() {
      if (!mounted || !_liveSharers.containsKey(userId)) return;
      final t = curve.value;
      setState(() {
        _liveSharers[userId]!.animatedPosition = LatLng(
          from.latitude + (to.latitude - from.latitude) * t,
          from.longitude + (to.longitude - from.longitude) * t,
        );
      });
    });
    ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        if (identical(_markerAnimControllers[userId], ctrl)) {
          _markerAnimControllers.remove(userId);
        }
        ctrl.dispose();
      }
    });
    ctrl.forward();
  }

  Future<void> _fetchUserProfile(String uid) async {
    if (_userCache.containsKey(uid)) {
      final user = _userCache[uid]!;
      if (mounted && _liveSharers.containsKey(uid)) {
        setState(() {
          final s = _liveSharers[uid]!;
          if (!s.isMe && (user.name?.isNotEmpty == true)) {
            s.name = user.name!;
          }
          s.profilePic = user.profilePic;
        });
      }
      return;
    }

    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (mounted && doc.exists && doc.data() != null) {
        final user = UserModel.fromMap(doc.data()!);
        _userCache[uid] = user;
        if (_liveSharers.containsKey(uid)) {
          setState(() {
            final s = _liveSharers[uid]!;
            if (!s.isMe && (user.name?.isNotEmpty == true)) {
              s.name = user.name!;
            }
            s.profilePic = user.profilePic;
          });
        }
      }
    } catch (e) {
      log('Error fetching user profile for $uid: $e');
    }
  }

  Future<void> _initViewerLocation() async {
    try {
      final fast = await LocationService.instance.getFastInitialPosition();
      if (mounted && fast != null) {
        _applyViewerPosition(fast);
      }

      final readiness =
          await LocationService.instance.checkLocationReadiness();
      if (!mounted) return;
      setState(() => _locationReadiness = readiness);
      if (readiness != LocationReadiness.ready) return;

      final current = await LocationService.instance.getCurrentLocation();
      if (mounted && current != null) {
        _applyViewerPosition(current);
      }

      final settings = defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 4,
              forceLocationManager: false,
              intervalDuration: const Duration(seconds: 3),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 4,
            );

      _myLocationSubscription =
          Geolocator.getPositionStream(locationSettings: settings).listen(
        (p) {
          if (!mounted) return;
          _applyViewerPosition(p);
          if (_showDirections) {
            _maybeRefreshRouteForMovement();
          }
        },
        onError: (e) {
          log('Viewer GPS stream error: $e');
        },
      );
    } catch (e) {
      log('Error initializing viewer location: $e');
    }
  }

  void _applyViewerPosition(Position p) {
    final myLatLng = LatLng(p.latitude, p.longitude);
    final currentUid = _safeCurrentUid();

    setState(() {
      _myPosition = myLatLng;
      _myAccuracy = p.accuracy.isFinite ? p.accuracy.clamp(4.0, 250.0) : 20.0;
      if (p.heading.isFinite && p.heading >= 0) {
        _myHeading = p.heading;
      }

      if (currentUid.isNotEmpty && _liveSharers.containsKey(currentUid)) {
        final me = _liveSharers[currentUid]!;
        final moved = const Distance().as(LengthUnit.Meter, me.position, myLatLng);
        me.position = myLatLng;
        me.animatedPosition = myLatLng;
        me.heading = p.heading >= 0 ? p.heading : me.heading;
        me.speed = p.speed >= 0 ? p.speed : me.speed;
        me.accuracy = _myAccuracy;
        if (moved >= 5.0) {
          final trail = _sharerTrails.putIfAbsent(currentUid, () => []);
          trail.add(myLatLng);
          if (trail.length > 180) trail.removeAt(0);
        }
      }
    });

    if (_autoFollow &&
        widget.isMe &&
        _focusedSharerId == currentUid &&
        _isMapReady) {
      _animatedMapMove(myLatLng, _mapController.camera.zoom);
    }
  }

  void _maybeRefreshFocusedAddress(LatLng point) {
    if (_lastGeocodedPoint != null) {
      final moved =
          const Distance().as(LengthUnit.Meter, _lastGeocodedPoint!, point);
      if (moved < 35.0) return;
    }
    _reverseGeocodeTarget(point);
  }

  Future<void> _reverseGeocodeTarget(LatLng point) async {
    _lastGeocodedPoint = point;
    _reverseCancel?.cancel();
    final token = CancelToken();
    _reverseCancel = token;
    try {
      final result = await LocationService.instance.reverseGeocode(
        point.latitude,
        point.longitude,
        cancelToken: token,
      );
      if (!mounted || token.isCancelled || result == null) return;
      setState(() {
        _placeName = result.placeName;
        _addressText = result.address;
      });
    } catch (_) {}
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    if (!_isMapReady) return;
    _cameraAnimController?.stop();
    _cameraAnimController?.dispose();
    _cameraAnimController = null;

    try {
      final camera = _mapController.camera;
      final latTween = Tween<double>(
        begin: camera.center.latitude,
        end: destLocation.latitude,
      );
      final lngTween = Tween<double>(
        begin: camera.center.longitude,
        end: destLocation.longitude,
      );
      final zoomTween = Tween<double>(begin: camera.zoom, end: destZoom);

      final ctrl = AnimationController(
        duration: const Duration(milliseconds: 520),
        vsync: this,
      );
      _cameraAnimController = ctrl;

      final anim = CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic);
      ctrl.addListener(() {
        if (!mounted || !_isMapReady) return;
        try {
          _mapController.move(
            LatLng(latTween.evaluate(anim), lngTween.evaluate(anim)),
            zoomTween.evaluate(anim),
          );
        } catch (_) {}
      });
      anim.addStatusListener((status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          if (identical(_cameraAnimController, ctrl)) {
            _cameraAnimController = null;
          }
          ctrl.dispose();
        }
      });
      ctrl.forward();
    } catch (_) {}
  }

  void _fitAllTargets() {
    if (!_isMapReady) return;
    final pts = <LatLng>[
      ..._activeSharers.map((s) => s.position),
      if (_myPosition != null) _myPosition!,
      if (_droppedPin != null) _droppedPin!.latLng,
    ];
    if (pts.isEmpty) return;

    if (pts.length == 1) {
      _animatedMapMove(pts.first, 16.5);
      return;
    }

    try {
      final bounds = LatLngBounds.fromPoints(pts);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(56, 150, 56, 260),
          maxZoom: 17.5,
        ),
      );
    } catch (_) {}
  }

  void _maybeRefreshRouteForMovement() {
    if (!_showDirections) return;
    final start = _resolveRouteOrigin();
    if (start == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final movedMeters = _lastRouteOrigin == null
        ? 999.0
        : const Distance().as(LengthUnit.Meter, _lastRouteOrigin!, start);
    if (movedMeters >= 30.0 && (now - _lastRouteFetchedMs) >= 15000) {
      _fetchInAppRoute(fitCamera: false);
    }
  }

  LatLng? _resolveRouteOrigin() {
    if (_myPosition != null) return _myPosition;
    final active = _activeSharers;
    if (active.length >= 2) {
      final me = active.where((s) => s.isMe);
      if (me.isNotEmpty) return me.first.position;
      return active.first.position;
    }
    return null;
  }

  Future<void> _fetchInAppRoute({bool fitCamera = true}) async {
    final start = _resolveRouteOrigin();
    final end = _navigationDestination;
    if (start == null || end == null) {
      if (mounted) {
        AppSnackBar.warning(
          context,
          'Turn on GPS to compute routes from your location.',
        );
      }
      return;
    }

    HapticFeedback.lightImpact();
    _routeCancel?.cancel();
    final token = CancelToken();
    _routeCancel = token;
    _lastRouteOrigin = start;
    _lastRouteFetchedMs = DateTime.now().millisecondsSinceEpoch;

    setState(() => _isLoadingRoute = true);

    try {
      final route = await LocationService.instance.fetchRoute(
        startLat: start.latitude,
        startLng: start.longitude,
        endLat: end.latitude,
        endLng: end.longitude,
        mode: _travelMode,
        cancelToken: token,
      );
      if (!mounted || token.isCancelled) return;
      setState(() {
        _activeRoute = route;
        _showDirections = true;
        _isLoadingRoute = false;
        _autoFollow = false;
      });
      if (fitCamera) {
        _fitPoints(route.points);
      }
    } catch (_) {
      if (mounted && !token.isCancelled) {
        setState(() => _isLoadingRoute = false);
      }
    }
  }

  void _fitPoints(List<LatLng> points) {
    if (!_isMapReady || points.isEmpty) return;
    try {
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(56, 170, 56, 280),
          maxZoom: 17.0,
        ),
      );
    } catch (_) {}
  }

  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    _searchCancel?.cancel();
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResults = const [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final token = CancelToken();
      _searchCancel = token;
      try {
        final bias = _myPosition ?? _focusedSharer?.position;
        final items = await LocationService.instance.searchPlaces(
          q,
          biasLat: bias?.latitude,
          biasLng: bias?.longitude,
          cancelToken: token,
        );
        if (!mounted || token.isCancelled) return;
        setState(() {
          _searchResults = items;
          _isSearching = false;
        });
      } catch (_) {
        if (mounted && !token.isCancelled) {
          setState(() => _isSearching = false);
        }
      }
    });
  }

  void _selectSearchResult(PlaceSearchResult item) {
    HapticFeedback.selectionClick();
    _searchFocusNode.unfocus();
    setState(() {
      _searchController.text = item.name;
      _searchResults = const [];
      _droppedPin = item;
      _placeName = item.name;
      _addressText =
          item.subtitle.isNotEmpty ? '${item.name}, ${item.subtitle}' : item.name;
      _autoFollow = false;
      _showDirections = false;
      _activeRoute = null;
    });
    _animatedMapMove(item.latLng, 16.2);
  }

  void _onMapTapped(TapPosition _, LatLng point) {
    if (_searchResults.isNotEmpty || _searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
      setState(() => _searchResults = const []);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _droppedPin = PlaceSearchResult(
        name: 'Dropped Pin',
        subtitle:
            '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
        latitude: point.latitude,
        longitude: point.longitude,
      );
      _placeName = 'Dropped Pin';
      _addressText =
          '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
      _autoFollow = false;
      _showDirections = false;
      _activeRoute = null;
    });
    _reverseGeocodePin(point);
  }

  Future<void> _reverseGeocodePin(LatLng point) async {
    final result =
        await LocationService.instance.reverseGeocode(point.latitude, point.longitude);
    if (!mounted || _droppedPin == null) return;
    if (_droppedPin!.latitude != point.latitude ||
        _droppedPin!.longitude != point.longitude) {
      return;
    }
    if (result != null) {
      setState(() {
        _droppedPin = PlaceSearchResult(
          name: result.placeName ?? 'Dropped Pin',
          subtitle: result.address,
          latitude: point.latitude,
          longitude: point.longitude,
        );
        _placeName = result.placeName ?? 'Dropped Pin';
        _addressText = result.address;
      });
    }
  }

  Future<void> _handleStopSharing() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2130),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Stop Sharing Location?',
          style: TextStyle(color: Colors.white, fontSize: 17),
        ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Stop Sharing',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    HapticFeedback.mediumImpact();

    final effectiveCurrentUser = _safeCurrentUid();
    final effectiveReceiver = widget.receiverId;

    if (widget.messageId != null &&
        effectiveCurrentUser.isNotEmpty &&
        effectiveReceiver != null) {
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
          _showDirections = false;
          _activeRoute = null;
        });
      }
    }
  }

  void _copyCoordinates() {
    final target = _droppedPin?.latLng ??
        _focusedSharer?.position ??
        LatLng(widget.initialLatitude, widget.initialLongitude);
    Clipboard.setData(
      ClipboardData(
        text:
            '${target.latitude.toStringAsFixed(6)}, ${target.longitude.toStringAsFixed(6)}',
      ),
    );
    HapticFeedback.selectionClick();
    AppSnackBar.success(context, 'Coordinates copied to clipboard');
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).round();
    if (mins < 1) return '1 min';
    if (mins >= 60) {
      final h = mins ~/ 60;
      final m = mins % 60;
      return m == 0 ? '$h hr' : '$h hr $m min';
    }
    return '$mins min';
  }

  String _formatLiveTimeRemaining(LiveSharer sharer) {
    if (!sharer.isActuallyLive) return 'Live ended';
    if (sharer.liveUntil == null) return 'Live active';
    final now = DateTime.now().millisecondsSinceEpoch;
    final diffMs = sharer.liveUntil! - now;
    if (diffMs <= 0) return 'Live ended';

    final totalMin = (diffMs / 60000).ceil();
    final endTime =
        DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(sharer.liveUntil!));
    if (totalMin > 60) {
      return 'Until $endTime (${totalMin ~/ 60}h ${totalMin % 60}m)';
    }
    return 'Until $endTime (${totalMin}m left)';
  }

  String _formatUpdatedAgo(int? updatedAt) {
    if (updatedAt == null) return '';
    final sec =
        ((DateTime.now().millisecondsSinceEpoch - updatedAt) / 1000).floor();
    if (sec < 10) return 'just now';
    if (sec < 60) return '${sec}s ago';
    final m = (sec / 60).floor();
    return '${m}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeSharers;
    final focused = _focusedSharer;
    final centerPos = focused?.position ??
        LatLng(widget.initialLatitude, widget.initialLongitude);
    final currentUid = _safeCurrentUid();
    final isMeSharing = currentUid.isNotEmpty &&
        _liveSharers.containsKey(currentUid) &&
        _liveSharers[currentUid]!.isActuallyLive;

    final spec = MapStyleRegistry.specFor(_currentStyle);

    return Scaffold(
      backgroundColor: spec.canvasBackgroundColor,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── Google Maps–style Open-Source Map Canvas ────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: centerPos,
              initialZoom: 16.2,
              minZoom: 3.0,
              maxZoom: 20.0,
              backgroundColor: spec.canvasBackgroundColor,
              onMapReady: () {
                if (mounted) {
                  setState(() => _isMapReady = true);
                  if (_bothUsersSharing) {
                    _fitAllTargets();
                  }
                }
              },
              onTap: _onMapTapped,
              onLongPress: _onMapTapped,
              onPositionChanged: (camera, hasGesture) {
                if (!mounted) return;
                final rotChanged =
                    (camera.rotation - _cameraRotationDeg).abs() > 0.5;
                if (hasGesture && _autoFollow) {
                  setState(() {
                    _autoFollow = false;
                    _cameraRotationDeg = camera.rotation;
                  });
                } else if (rotChanged) {
                  setState(() => _cameraRotationDeg = camera.rotation);
                }
              },
            ),
            children: [
              ...WorshipMapTiles.buildTileLayers(
                context,
                _currentStyle,
                keepBuffer: 3,
                panBuffer: 1,
              ),

              // Breadcrumb Live Movement Trails
              PolylineLayer(
                polylines: [
                  for (final s in active)
                    if ((_sharerTrails[s.userId]?.length ?? 0) >= 2)
                      Polyline(
                        points: _sharerTrails[s.userId]!,
                        strokeWidth: 3.5,
                        color: (s.isMe
                                ? const Color(0xFF1A73E8)
                                : const Color(0xFF00E676))
                            .withValues(alpha: 0.65),
                        pattern: StrokePattern.dashed(
                          segments: const [10, 6],
                        ),
                      ),
                ],
              ),

              // Google Maps Navigation Route Polyline
              if (_showDirections &&
                  _activeRoute != null &&
                  _activeRoute!.points.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _activeRoute!.points,
                      strokeWidth: _travelMode == TravelMode.walking ? 6.0 : 8.5,
                      borderStrokeWidth: 2.2,
                      borderColor: _travelMode == TravelMode.walking
                          ? const Color(0xFF0F7657)
                          : const Color(0xFF0D47A1),
                      color: _travelMode == TravelMode.walking
                          ? const Color(0xFF1E8E6E)
                          : const Color(0xFF1A73E8),
                      pattern: _travelMode == TravelMode.walking
                          ? const StrokePattern.dotted(spacingFactor: 1.45)
                          : const StrokePattern.solid(),
                      strokeCap: StrokeCap.round,
                      strokeJoin: StrokeJoin.round,
                    ),
                  ],
                ),

              // Real-Meter GPS Accuracy Circles
              CircleLayer(
                circles: [
                  for (final s in active)
                    CircleMarker(
                      point: s.animatedPosition,
                      radius: (s.accuracy ?? (s.isActuallyLive ? 28 : 16))
                          .clamp(8.0, 220.0),
                      useRadiusInMeter: true,
                      color: (s.isMe
                              ? const Color(0xFF1A73E8)
                              : const Color(0xFF00E676))
                          .withValues(alpha: 0.14),
                      borderColor: (s.isMe
                              ? const Color(0xFF1A73E8)
                              : const Color(0xFF00E676))
                          .withValues(alpha: 0.42),
                      borderStrokeWidth: 1.4,
                    ),
                  if (_myPosition != null && !isMeSharing)
                    CircleMarker(
                      point: _myPosition!,
                      radius: _myAccuracy,
                      useRadiusInMeter: true,
                      color: const Color(0xFF1A73E8).withValues(alpha: 0.16),
                      borderColor:
                          const Color(0xFF1A73E8).withValues(alpha: 0.45),
                      borderStrokeWidth: 1.4,
                    ),
                ],
              ),

              // User Blue Dot + Live Sharers + Dropped Pin Markers
              MarkerLayer(
                markers: [
                  if (_myPosition != null && !isMeSharing)
                    Marker(
                      point: _myPosition!,
                      width: 64,
                      height: 64,
                      child: _buildMyLocationDotWithHeading(),
                    ),
                  ...active.map(
                    (sharer) => Marker(
                      point: sharer.animatedPosition,
                      width: 110,
                      height: 102,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _focusedSharerId = sharer.userId;
                            _droppedPin = null;
                            _autoFollow = true;
                          });
                          _animatedMapMove(sharer.position, 16.8);
                          _reverseGeocodeTarget(sharer.position);
                        },
                        child: _buildUserPinMarker(sharer),
                      ),
                    ),
                  ),
                  if (_droppedPin != null)
                    Marker(
                      point: _droppedPin!.latLng,
                      width: 120,
                      height: 76,
                      alignment: Alignment.topCenter,
                      child: _buildDroppedPinMarker(_droppedPin!),
                    ),
                ],
              ),

              // Distance Scale Bar (adapts color cleanly to basemap)
              Scalebar(
                alignment: Alignment.topLeft,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top +
                      (_showDirections && _activeRoute != null ? 148 : 74),
                  left: 14,
                ),
                textStyle: TextStyle(
                  color: spec.isDarkCanvas ? Colors.white70 : Colors.black87,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                lineColor: spec.isDarkCanvas ? Colors.white70 : Colors.black87,
              ),
            ],
          ),

          // ── Top Floating Google-Maps Search Bar + Next-Turn Banner ──────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTopSearchBar(active),
                  if (_searchResults.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _buildSearchResultsCard(),
                  ] else if (_showDirections &&
                      _activeRoute != null &&
                      _activeRoute!.steps.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildNextTurnBanner(_activeRoute!.steps.first),
                  ],
                ],
              ),
            ),
          ),

          // ── Right Floating Map Controls (Layers, Compass, Zoom, My GPS) ─
          Positioned(
            right: 12,
            top: MediaQuery.of(context).padding.top +
                (_showDirections && _activeRoute != null ? 156 : 82),
            child: _buildRightMapControls(isMeSharing),
          ),

          // ── Google Maps–Style Draggable Bottom Sheet ────────────────────
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.27,
            minChildSize: 0.16,
            maxChildSize: 0.84,
            snap: true,
            snapSizes: const [0.24, 0.48, 0.84],
            builder: (context, scrollController) => _buildDraggableBottomSheet(
              scrollController: scrollController,
              active: active,
              focused: focused,
              isMeSharing: isMeSharing,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSearchBar(List<LiveSharer> active) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1E2B).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 22,
            ),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              decoration: InputDecoration(
                hintText: widget.isLive
                    ? 'Search place or coordinates...'
                    : (_placeName ?? 'Search here...'),
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4FC3F7),
                ),
              ),
            )
          else if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
              onPressed: () {
                _searchController.clear();
                setState(() => _searchResults = const []);
              },
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: _fitAllTargets,
                child: _buildTopBarAvatars(active),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsCard() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1E2B).withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: _searchResults.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          itemBuilder: (_, idx) {
            final item = _searchResults[idx];
            return ListTile(
              dense: true,
              leading: const CircleAvatar(
                radius: 16,
                backgroundColor: Color(0xFF282C3E),
                child: Icon(
                  Icons.place_rounded,
                  color: Color(0xFF4FC3F7),
                  size: 18,
                ),
              ),
              title: Text(
                item.name,
                maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: item.subtitle.isNotEmpty
                ? Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                  )
                : null,
            onTap: () => _selectSearchResult(item),
          );
        },
      ),
      ),
    );
  }

  Widget _buildNextTurnBanner(RouteStep firstStep) {
    final route = _activeRoute!;
    return GestureDetector(
      onTap: () {
        if (_sheetController.isAttached) {
          _sheetController.animateTo(
            0.84,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF0F7657),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _maneuverIcon(firstStep.maneuverType, firstStep.maneuverModifier),
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    firstStep.instruction,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatDuration(route.durationSeconds)} (${_formatDistance(route.distanceMeters)}) • ${route.mode.label}${route.isFallbackEstimate ? ' est.' : ''}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
              tooltip: 'End route preview',
              onPressed: () {
                setState(() {
                  _showDirections = false;
                  _activeRoute = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightMapControls(bool isMeSharing) {
    final isCompassVisible = _cameraRotationDeg.abs() > 1.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCircleControl(
          icon: const Icon(Icons.layers_rounded, color: Colors.white, size: 21),
          tooltip: 'Map type & layers',
          onTap: _openMapTypeSheet,
        ),
        const SizedBox(height: 10),
        if (isCompassVisible) ...[
          _buildCircleControl(
            icon: Transform.rotate(
              angle: _cameraRotationDeg * (math.pi / 180),
              child: const Icon(
                Icons.explore_rounded,
                color: Color(0xFFFFB300),
                size: 22,
              ),
            ),
            tooltip: 'Reset north',
            onTap: () {
              if (!_isMapReady) return;
              HapticFeedback.selectionClick();
              _mapController.rotate(0.0);
              setState(() => _cameraRotationDeg = 0.0);
            },
          ),
          const SizedBox(height: 10),
        ],
        if (_activeSharers.length > 1 || _droppedPin != null || _myPosition != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildCircleControl(
              icon: const Icon(
                Icons.zoom_out_map_rounded,
                color: Color(0xFF00E676),
                size: 20,
              ),
              tooltip: 'Fit all markers',
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _autoFollow = false;
                  _focusedSharerId = null;
                });
                _fitAllTargets();
              },
            ),
          ),
        // Zoom capsule
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1B1E2B).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
                onTap: () {
                  if (!_isMapReady) return;
                  final z = (_mapController.camera.zoom + 1).clamp(3.0, 20.0);
                  _animatedMapMove(_mapController.camera.center, z);
                },
                child: const SizedBox(
                  width: 42,
                  height: 38,
                  child: Icon(Icons.add_rounded, color: Colors.white, size: 20),
                ),
              ),
              Container(
                width: 24,
                height: 1,
                color: Colors.white.withValues(alpha: 0.12),
              ),
              InkWell(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(22)),
                onTap: () {
                  if (!_isMapReady) return;
                  final z = (_mapController.camera.zoom - 1).clamp(3.0, 20.0);
                  _animatedMapMove(_mapController.camera.center, z);
                },
                child: const SizedBox(
                  width: 42,
                  height: 38,
                  child: Icon(Icons.remove_rounded, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Primary Google Maps My Location / Re-center FAB
        _buildCircleControl(
          size: 48,
          backgroundColor: _autoFollow
              ? const Color(0xFF1A73E8)
              : const Color(0xFF1B1E2B).withValues(alpha: 0.95),
          icon: Icon(
            _myPosition != null
                ? (_autoFollow
                    ? Icons.gps_fixed_rounded
                    : Icons.my_location_rounded)
                : Icons.location_searching_rounded,
            color: _autoFollow ? Colors.white : const Color(0xFF4FC3F7),
            size: 22,
          ),
          tooltip: _myPosition != null ? 'Center on location' : 'Enable GPS',
          onTap: () async {
            HapticFeedback.lightImpact();
            if (_myPosition == null &&
                _locationReadiness != LocationReadiness.ready) {
              if (_locationReadiness == LocationReadiness.serviceDisabled) {
                await LocationService.instance.openLocationSettings();
              } else if (_locationReadiness ==
                  LocationReadiness.permissionDeniedForever) {
                await LocationService.instance.openAppSettings();
              }
              await _initViewerLocation();
              return;
            }
            setState(() => _autoFollow = true);
            final target = _myPosition ??
                _focusedSharer?.position ??
                LatLng(widget.initialLatitude, widget.initialLongitude);
            _animatedMapMove(target, 16.8);
          },
        ),
      ],
    );
  }

  Widget _buildCircleControl({
    required Widget icon,
    required String tooltip,
    required VoidCallback onTap,
    double size = 42,
    Color? backgroundColor,
  }) {
    return Material(
      color: backgroundColor ??
          const Color(0xFF1B1E2B).withValues(alpha: 0.94),
      shape: CircleBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      elevation: 5,
      shadowColor: Colors.black54,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(width: size, height: size, child: Center(child: icon)),
        ),
      ),
    );
  }

  Widget _buildMyLocationDotWithHeading() {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (_myHeading != null)
          Transform.rotate(
            angle: _myHeading! * (math.pi / 180),
            child: CustomPaint(
              size: const Size(56, 56),
              painter: _HeadingConePainter(),
            ),
          ),
        AnimatedBuilder(
          animation: _pulseController,
          builder: (_, __) {
            final s = 0.8 + (_pulseController.value * 0.65);
            return Transform.scale(
              scale: s,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1A73E8).withValues(
                    alpha: (1.0 - _pulseController.value) * 0.35,
                  ),
                ),
              ),
            );
          },
        ),
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1A73E8),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A73E8).withValues(alpha: 0.55),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDroppedPinMarker(PlaceSearchResult pin) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFFEA4335),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.place_rounded, color: Colors.white, size: 20),
        ),
        const CustomPaint(
          size: Size(12, 7),
          painter: _PinTipPainter(color: Color(0xFFEA4335)),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            pin.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBarAvatars(List<LiveSharer> active) {
    if (active.length <= 1) {
      final s = active.isNotEmpty ? active.first : null;
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: (s?.isActuallyLive ?? false)
                ? const Color(0xFF00E676)
                : const Color(0xFF4FC3F7),
            width: 2,
          ),
        ),
        child: ClipOval(
          child: (s?.profilePic != null && s!.profilePic!.isNotEmpty)
              ? CachedNetworkImage(
                  imageUrl: s.profilePic!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      const Icon(Icons.person, color: Colors.white54, size: 18),
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.person, color: Colors.white54, size: 18),
                )
              : const Icon(Icons.person, color: Colors.white54, size: 18),
        ),
      );
    }

    return SizedBox(
      width: 44,
      height: 34,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: _buildMiniAvatarCircle(active[0], const Color(0xFF1A73E8)),
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
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
        color: const Color(0xFF1B1E2B),
      ),
      child: ClipOval(
        child: (s.profilePic != null && s.profilePic!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: s.profilePic!,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    const Icon(Icons.person, color: Colors.white54, size: 15),
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.person, color: Colors.white54, size: 15),
              )
            : const Icon(Icons.person, color: Colors.white54, size: 15),
      ),
    );
  }

  Widget _buildUserPinMarker(LiveSharer sharer) {
    final isActuallyLive = sharer.isActuallyLive;
    final ringColor =
        sharer.isMe ? const Color(0xFF1A73E8) : const Color(0xFF00E676);
    final isSelected = _focusedSharerId == sharer.userId;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            if (sharer.heading != null && sharer.heading! >= 0)
              Transform.rotate(
                angle: sharer.heading! * (math.pi / 180),
                child: const CustomPaint(
                  size: Size(68, 68),
                  painter: _HeadingConePainter(),
                ),
              ),
            if (isActuallyLive)
              AnimatedBuilder(
                animation: _pulseController,
                builder: (_, __) {
                  final scale = 1.0 + (_pulseController.value * 0.46);
                  final opacity =
                      (1.0 - _pulseController.value).clamp(0.0, 1.0);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ringColor.withValues(alpha: 0.30 * opacity),
                      ),
                    ),
                  );
                },
              ),
            Container(
              width: isSelected ? 48 : 44,
              height: isSelected ? 48 : 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1B1E2B),
                border: Border.all(
                  color: isActuallyLive ? ringColor : Colors.white,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isActuallyLive ? ringColor : Colors.black)
                        .withValues(alpha: 0.45),
                    blurRadius: 10,
                    spreadRadius: 1.5,
                  ),
                ],
              ),
              child: ClipOval(
                child: (sharer.profilePic != null &&
                        sharer.profilePic!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: sharer.profilePic!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 24,
                        ),
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 24,
                        ),
                      )
                    : Center(
                        child: Text(
                          sharer.name.isNotEmpty
                              ? sharer.name[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
        CustomPaint(
          size: const Size(14, 8),
          painter: _PinTipPainter(
            color: isActuallyLive ? ringColor : Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          constraints: const BoxConstraints(maxWidth: 106),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.84),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActuallyLive
                  ? ringColor.withValues(alpha: 0.55)
                  : Colors.white24,
              width: 0.6,
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
              Flexible(
                child: Text(
                  sharer.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Google Maps–style Map Type Picker Bottom Sheet.
  void _openMapTypeSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF171926),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
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
                        const Text(
                          'Map type',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.84,
                      children: [
                        for (final style in AppMapStyle.values)
                          _buildMapTypePreviewTile(style, ctx),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapTypePreviewTile(AppMapStyle style, BuildContext sheetCtx) {
    final spec = MapStyleRegistry.specFor(style);
    final selected = _currentStyle == style;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _currentStyle = style);
        MapStyleRegistry.saveStyle(style);
        Navigator.pop(sheetCtx);
      },
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  spec.previewPrimaryColor,
                  spec.previewSecondaryColor,
                ],
              ),
              border: Border.all(
                color: selected
                    ? const Color(0xFF4FC3F7)
                    : Colors.white.withValues(alpha: 0.16),
                width: selected ? 2.5 : 1.0,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF4FC3F7).withValues(alpha: 0.35),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(spec.icon, color: spec.previewAccentColor, size: 28),
                if (selected)
                  const Positioned(
                    top: 5,
                    right: 5,
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF4FC3F7),
                      size: 16,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                spec.title,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? const Color(0xFF4FC3F7) : Colors.white,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraggableBottomSheet({
    required ScrollController scrollController,
    required List<LiveSharer> active,
    required LiveSharer? focused,
    required bool isMeSharing,
  }) {
    final targetLatLng = _droppedPin?.latLng ??
        focused?.position ??
        LatLng(widget.initialLatitude, widget.initialLongitude);
    final distanceMeters = _myPosition != null
        ? const Distance().as(LengthUnit.Meter, _myPosition!, targetLatLng)
        : null;
    final speedKmh = (focused?.speed != null &&
            focused!.speed!.isFinite &&
            focused.speed! >= 0.8)
        ? (focused.speed! * 3.6)
        : null;

    final primaryTitle = _droppedPin != null
        ? _droppedPin!.name
        : (_placeName?.isNotEmpty == true
            ? _placeName!
            : (focused?.name ?? widget.sharerName ?? 'Shared Location'));

    final statusParts = <String>[
      if (_droppedPin != null)
        'Selected Pin'
      else if (focused != null && focused.isActuallyLive)
        _formatLiveTimeRemaining(focused)
      else if (widget.isLive)
        'Live ended'
      else
        'Shared Pin',
      if (focused != null && focused.isActuallyLive && focused.updatedAt != null)
        'Updated ${_formatUpdatedAgo(focused.updatedAt)}',
      if (distanceMeters != null && distanceMeters > 10)
        '${_formatDistance(distanceMeters)} away',
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161826).withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
          children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title, Speed Pill & Close Pin / Clear
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (_droppedPin == null &&
                            focused != null &&
                            focused.isActuallyLive)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(
                              color: Color(0xFF00E676),
                              shape: BoxShape.circle,
                            ),
                          ),
                        Flexible(
                          child: Text(
                            primaryTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (speedKmh != null && _droppedPin == null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676)
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${speedKmh.toStringAsFixed(0)} km/h',
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      statusParts.join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: (focused?.isActuallyLive ?? false) &&
                                _droppedPin == null
                            ? const Color(0xFF00E676)
                            : Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_droppedPin != null)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _droppedPin = null;
                      _showDirections = false;
                      _activeRoute = null;
                    });
                    if (focused != null) {
                      _reverseGeocodeTarget(focused.position);
                    }
                  },
                  child: const Text(
                    'Clear Pin',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),

          // Google Maps Action Pill Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (_canGetDirections) ...[
                  _buildActionPill(
                    icon: _isLoadingRoute
                        ? Icons.hourglass_top_rounded
                        : (_showDirections
                            ? Icons.directions_off_rounded
                            : Icons.directions_rounded),
                    label: _showDirections ? 'Hide Route' : 'Directions',
                    filled: true,
                    color: const Color(0xFF1A73E8),
                    onTap: () {
                      if (_showDirections) {
                        setState(() {
                          _showDirections = false;
                          _activeRoute = null;
                        });
                      } else {
                        _fetchInAppRoute();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                _buildActionPill(
                  icon: Icons.open_in_new_rounded,
                  label: 'Google Maps',
                  color: Colors.white,
                  onTap: () => LocationService.instance.openExternalDirections(
                    targetLatLng.latitude,
                    targetLatLng.longitude,
                    mode: _travelMode,
                  ),
                ),
                const SizedBox(width: 8),
                _buildActionPill(
                  icon: Icons.copy_rounded,
                  label: 'Copy Coords',
                  color: Colors.white70,
                  onTap: _copyCoordinates,
                ),
                if (isMeSharing) ...[
                  const SizedBox(width: 8),
                  _buildActionPill(
                    icon: Icons.stop_circle_outlined,
                    label: 'Stop Sharing',
                    filled: true,
                    color: const Color(0xFFE53935),
                    onTap: _handleStopSharing,
                  ),
                ],
              ],
            ),
          ),

          // Travel Mode Switcher (Drive / Walk / Cycle) when Directions active
          if (_showDirections || _canGetDirections) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (final mode in TravelMode.values)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: mode != TravelMode.cycling ? 8 : 0,
                      ),
                      child: _buildTravelModeChip(mode),
                    ),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 12),

          // Address Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF202334),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: Color(0xFF4FC3F7),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _addressText ??
                        '${targetLatLng.latitude.toStringAsFixed(5)}, ${targetLatLng.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Active Live Sharers Cards
          if (active.length > 1) ...[
            const SizedBox(height: 16),
            const Text(
              'ACTIVE LIVE SHARERS',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 54,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: active.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, idx) {
                  final s = active[idx];
                  final selected = _focusedSharerId == s.userId;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _focusedSharerId = s.userId;
                        _droppedPin = null;
                        _autoFollow = true;
                      });
                      _animatedMapMove(s.position, 16.8);
                      _reverseGeocodeTarget(s.position);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF1A73E8).withValues(alpha: 0.16)
                            : const Color(0xFF202334),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: s.isMe
                              ? const Color(0xFF1A73E8)
                              : const Color(0xFF00E676),
                          width: selected ? 1.6 : 0.9,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundImage: (s.profilePic != null &&
                                    s.profilePic!.isNotEmpty)
                                ? CachedNetworkImageProvider(s.profilePic!)
                                : null,
                            child: (s.profilePic == null ||
                                    s.profilePic!.isEmpty)
                                ? Text(
                                    s.name.isNotEmpty ? s.name[0] : 'U',
                                    style: const TextStyle(fontSize: 12),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                s.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _formatLiveTimeRemaining(s),
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // Turn-by-Turn Navigation Steps (when Directions active)
          if (_showDirections &&
              _activeRoute != null &&
              _activeRoute!.steps.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'STEPS • ${_formatDuration(_activeRoute!.durationSeconds)} (${_formatDistance(_activeRoute!.distanceMeters)})',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            for (final step in _activeRoute!.steps)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF202334),
                  child: Icon(
                    _maneuverIcon(step.maneuverType, step.maneuverModifier),
                    color: const Color(0xFF4FC3F7),
                    size: 18,
                  ),
                ),
                title: Text(
                  step.instruction,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: Text(
                  _formatDistance(step.distanceMeters),
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  setState(() => _autoFollow = false);
                  _animatedMapMove(step.location, 17.5);
                },
              ),
          ],
        ],
      ),
      ),
    );
  }

  Widget _buildActionPill({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return Material(
      color: filled ? color : const Color(0xFF202334),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: filled
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: filled ? Colors.white : color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.white : color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTravelModeChip(TravelMode mode) {
    final selected = _travelMode == mode;
    final icon = switch (mode) {
      TravelMode.driving => Icons.directions_car_rounded,
      TravelMode.walking => Icons.directions_walk_rounded,
      TravelMode.cycling => Icons.directions_bike_rounded,
    };
    return GestureDetector(
      onTap: () {
        if (_travelMode == mode && _showDirections) return;
        HapticFeedback.selectionClick();
        setState(() => _travelMode = mode);
        if (_showDirections || _canGetDirections) {
          _fetchInAppRoute(fitCamera: true);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1A73E8).withValues(alpha: 0.22)
              : const Color(0xFF202334),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? const Color(0xFF4FC3F7)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? const Color(0xFF4FC3F7) : Colors.white60,
            ),
            const SizedBox(width: 5),
            Text(
              mode.label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white60,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _maneuverIcon(String type, String? modifier) {
    final mod = modifier ?? '';
    if (type == 'arrive') return Icons.flag_rounded;
    if (type.contains('roundabout') || type == 'rotary') {
      return Icons.roundabout_right_rounded;
    }
    if (mod.contains('uturn')) return Icons.u_turn_left_rounded;
    if (mod.contains('sharp left')) return Icons.turn_sharp_left_rounded;
    if (mod.contains('sharp right')) return Icons.turn_sharp_right_rounded;
    if (mod.contains('slight left')) return Icons.turn_slight_left_rounded;
    if (mod.contains('slight right')) return Icons.turn_slight_right_rounded;
    if (mod.contains('left')) return Icons.turn_left_rounded;
    if (mod.contains('right')) return Icons.turn_right_rounded;
    return Icons.straight_rounded;
  }
}

class _HeadingConePainter extends CustomPainter {
  const _HeadingConePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF1A73E8).withValues(alpha: 0.45),
          const Color(0xFF1A73E8).withValues(alpha: 0.0),
        ],
      ).createShader(rect);

    // Points upward (-90 degrees) for bearing = 0 (North).
    canvas.drawArc(
      rect,
      -math.pi / 2 - (math.pi / 5),
      (math.pi / 5) * 2,
      true,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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
  bool shouldRepaint(covariant _PinTipPainter oldDelegate) =>
      oldDelegate.color != color;
}
