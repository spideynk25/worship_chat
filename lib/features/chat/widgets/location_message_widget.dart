import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/location_service.dart';
import 'package:worship_chat/common/utils/map_style_config.dart';
import 'package:worship_chat/features/chat/screens/live_location_screen.dart';

class LocationMessageWidget extends StatefulWidget {
  final String messageType; // 'location' or 'live_location'
  final String? locationData;
  final bool isMe;
  final String? messageId;
  final String? currentUserId;
  final String? receiverId;
  final String? senderName;
  final String? senderProfilePic;

  const LocationMessageWidget({
    super.key,
    required this.messageType,
    required this.locationData,
    required this.isMe,
    this.messageId,
    this.currentUserId,
    this.receiverId,
    this.senderName,
    this.senderProfilePic,
  });

  @override
  State<LocationMessageWidget> createState() => _LocationMessageWidgetState();
}

class _LocationMessageWidgetState extends State<LocationMessageWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final MapController _mapController;
  Timer? _countdownTimer;
  bool _isMapReady = false;
  LatLng? _lastMapCenter;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    MapStyleRegistry.loadSavedStyle();

    if (widget.messageType == 'live_location') {
      _countdownTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (mounted) setState(() {});
      });
      _checkAndResumeTracking();
    }
  }

  void _checkAndResumeTracking() {
    if (!widget.isMe || widget.messageType != 'live_location') {
      return;
    }
    if (widget.messageId == null ||
        widget.currentUserId == null ||
        widget.receiverId == null) {
      return;
    }

    final data = _parseData();
    if (data != null && data['isLive'] == true) {
      final liveUntil = (data['liveUntil'] as num?)?.toInt();
      final now = DateTime.now().millisecondsSinceEpoch;
      if (liveUntil != null && liveUntil > now) {
        if (!LocationService.instance.isTracking(widget.messageId!)) {
          final remaining = Duration(milliseconds: liveUntil - now);
          LocationService.instance.startLiveLocationTracking(
            messageId: widget.messageId!,
            currentUserId: widget.currentUserId!,
            receiverId: widget.receiverId!,
            duration: remaining,
            explicitLiveUntil: liveUntil,
          );
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant LocationMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locationData != widget.locationData ||
        oldWidget.messageType != widget.messageType) {
      final updatedData = _parseData();
      if (updatedData != null) {
        final newLat = (updatedData['latitude'] as num?)?.toDouble();
        final newLng = (updatedData['longitude'] as num?)?.toDouble();
        if (newLat != null && newLng != null) {
          final nextCenter = LatLng(newLat, newLng);
          if (_isMapReady &&
              (_lastMapCenter == null ||
                  _lastMapCenter!.latitude != newLat ||
                  _lastMapCenter!.longitude != newLng)) {
            _lastMapCenter = nextCenter;
            try {
              _mapController.move(nextCenter, 15.2);
            } catch (_) {}
          }
        }
      }
      setState(() {});
      _checkAndResumeTracking();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _countdownTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _parseData() {
    if (widget.locationData == null || widget.locationData!.isEmpty) return null;
    try {
      if (widget.locationData!.startsWith('{')) {
        return jsonDecode(widget.locationData!) as Map<String, dynamic>;
      } else if (widget.locationData!.contains(',')) {
        final parts = widget.locationData!.split(',');
        return {
          'latitude': double.tryParse(parts[0].trim()),
          'longitude': double.tryParse(parts[1].trim()),
          'isLive': false,
        };
      }
    } catch (e) {
      log('Error parsing location data: $e');
    }
    return null;
  }

  Future<void> _handleStopSharing() async {
    HapticFeedback.mediumImpact();
    if (widget.messageId == null ||
        widget.currentUserId == null ||
        widget.receiverId == null) {
      return;
    }

    try {
      await LocationService.instance.stopLiveLocationSharing(
        messageId: widget.messageId!,
        currentUserId: widget.currentUserId!,
        receiverId: widget.receiverId!,
      );
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      log('Error stopping live sharing: $e');
    }
  }

  void _handleLocationTap(double lat, double lng, Map<String, dynamic> data) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LiveLocationScreen(
          messageId: widget.messageId,
          currentUserId: widget.currentUserId,
          receiverId: widget.receiverId,
          sharerId: data['sharerId']?.toString(),
          sharerName:
              widget.senderName ?? (widget.isMe ? 'You' : 'Shared Location'),
          sharerProfilePic: widget.senderProfilePic,
          initialLatitude: lat,
          initialLongitude: lng,
          isLive: widget.messageType == 'live_location' &&
              (data['isLive'] == true),
          liveUntil: (data['liveUntil'] as num?)?.toInt(),
          updatedAt: (data['updatedAt'] as num?)?.toInt(),
          isMe: widget.isMe,
          initialPlaceName: data['placeName']?.toString(),
          initialAddress: data['address']?.toString(),
          initialAccuracy: (data['accuracy'] as num?)?.toDouble(),
          initialHeading: (data['heading'] as num?)?.toDouble(),
          initialSpeed: (data['speed'] as num?)?.toDouble(),
        ),
      ),
    );
  }

  String _formatAgo(int? updatedAtMs) {
    if (updatedAtMs == null) return '';
    final diffSec =
        ((DateTime.now().millisecondsSinceEpoch - updatedAtMs) / 1000).floor();
    if (diffSec < 10) return 'Updated just now';
    if (diffSec < 60) return 'Updated ${diffSec}s ago';
    final mins = (diffSec / 60).floor();
    if (mins < 60) return 'Updated ${mins}m ago';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final data = _parseData();
    if (data == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off, color: Colors.orange, size: 20),
            SizedBox(width: 8),
            Text(
              'Location unavailable',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final double lat = (data['latitude'] as num?)?.toDouble() ?? 0.0;
    final double lng = (data['longitude'] as num?)?.toDouble() ?? 0.0;
    final double? accuracy = (data['accuracy'] as num?)?.toDouble();
    final double? speed = (data['speed'] as num?)?.toDouble();
    final int? updatedAt = (data['updatedAt'] as num?)?.toInt();
    final String? placeName = (data['placeName'] as String?)?.trim();
    final String? address = (data['address'] as String?)?.trim();
    final bool isLiveType = widget.messageType == 'live_location';
    final int? liveUntil = (data['liveUntil'] as num?)?.toInt();
    final bool rawIsLive = data['isLive'] == true;
    final now = DateTime.now().millisecondsSinceEpoch;
    final bool isActuallyLive =
        isLiveType && rawIsLive && (liveUntil == null || liveUntil > now);

    final point = LatLng(lat, lng);
    _lastMapCenter ??= point;

    String statusSubtitle;
    if (isLiveType) {
      if (isActuallyLive && liveUntil != null) {
        final remainingMin = ((liveUntil - now) / 60000).ceil();
        if (remainingMin > 60) {
          final hours = (remainingMin / 60).floor();
          final mins = remainingMin % 60;
          statusSubtitle = 'Live for ${hours}h ${mins}m';
        } else {
          statusSubtitle = 'Live for $remainingMin min';
        }
        final ago = _formatAgo(updatedAt);
        if (ago.isNotEmpty) {
          statusSubtitle = '$statusSubtitle • $ago';
        }
      } else {
        statusSubtitle = 'Live location ended';
      }
    } else if (address != null && address.isNotEmpty) {
      statusSubtitle = address;
    } else {
      statusSubtitle = '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    }

    final titleText = isLiveType
        ? 'Live Location'
        : (placeName != null && placeName.isNotEmpty
            ? placeName
            : 'Current Location');

    final speedKmh =
        (speed != null && speed.isFinite && speed >= 0.8) ? (speed * 3.6) : null;

    return Container(
      constraints: const BoxConstraints(minWidth: 235, maxWidth: 286),
      decoration: BoxDecoration(
        color: const Color(0xFF161826),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActuallyLive
              ? const Color(0xFF00E676).withValues(alpha: 0.38)
              : Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => _handleLocationTap(lat, lng, data),
            child: SizedBox(
              height: 136,
              child: ValueListenableBuilder<AppMapStyle>(
                valueListenable: MapStyleRegistry.styleNotifier,
                builder: (context, activeStyle, _) {
                  final spec = MapStyleRegistry.specFor(activeStyle);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(color: spec.canvasBackgroundColor),
                      IgnorePointer(
                        child: RepaintBoundary(
                          child: FlutterMap(
                            key: ValueKey(
                              'osm_map_${widget.messageId ?? "msg"}_${activeStyle.name}',
                            ),
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: point,
                              initialZoom: 15.2,
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.none,
                              ),
                              onMapReady: () {
                                _isMapReady = true;
                              },
                            ),
                            children: [
                              ...WorshipMapTiles.buildTileLayers(
                                context,
                                activeStyle,
                                keepBuffer: 1,
                                panBuffer: 0,
                              ),
                              if (accuracy != null && accuracy > 0)
                                CircleLayer(
                                  circles: [
                                    CircleMarker(
                                      point: point,
                                      radius: accuracy.clamp(8.0, 120.0),
                                      useRadiusInMeter: true,
                                      color: (isActuallyLive
                                              ? const Color(0xFF00E676)
                                              : const Color(0xFF1A73E8))
                                          .withValues(alpha: 0.15),
                                      borderColor: (isActuallyLive
                                              ? const Color(0xFF00E676)
                                              : const Color(0xFF1A73E8))
                                          .withValues(alpha: 0.45),
                                      borderStrokeWidth: 1.2,
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Subtle bottom vignette for crisp badge readability
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.16),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.34),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Center Marker (Google Blue/Red Pin or Live Radar Pin)
                      if (isActuallyLive) ...[
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Container(
                              width: 36 + (_pulseController.value * 24),
                              height: 36 + (_pulseController.value * 24),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF00E676).withValues(
                                  alpha: 0.30 * (1.0 - _pulseController.value),
                                ),
                              ),
                            );
                          },
                        ),
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00B074),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00E676)
                                    .withValues(alpha: 0.5),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.radar_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ] else
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: isLiveType
                                    ? Colors.grey[700]
                                    : const Color(0xFFEA4335),
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2.2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Icon(
                                isLiveType
                                    ? Icons.location_off_rounded
                                    : Icons.place_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            Container(
                              width: 5,
                              height: 3,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ),

                      // Top-left Live / Current Status Pill
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121420)
                                .withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isActuallyLive
                                  ? const Color(0xFF00E676)
                                      .withValues(alpha: 0.55)
                                  : Colors.white.withValues(alpha: 0.16),
                              width: 0.7,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isActuallyLive) ...[
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF00E676),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                const Text(
                                  'LIVE',
                                  style: TextStyle(
                                    color: Color(0xFF00E676),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ] else ...[
                                Icon(
                                  isLiveType
                                      ? Icons.timer_off_outlined
                                      : Icons.my_location_rounded,
                                  color: isLiveType
                                      ? Colors.grey
                                      : const Color(0xFF4FC3F7),
                                  size: 11,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isLiveType ? 'ENDED' : 'CURRENT',
                                  style: TextStyle(
                                    color: isLiveType
                                        ? Colors.grey
                                        : const Color(0xFF4FC3F7),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      if (isActuallyLive && speedKmh != null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF121420)
                                  .withValues(alpha: 0.82),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${speedKmh.toStringAsFixed(0)} km/h',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),

                      // Bottom-right Tap Action Pill
                      Positioned(
                        bottom: 7,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121420)
                                .withValues(alpha: 0.84),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isActuallyLive
                                  ? const Color(0xFF00E676)
                                      .withValues(alpha: 0.4)
                                  : Colors.white.withValues(alpha: 0.16),
                              width: 0.7,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isLiveType ? 'Track Live' : 'Open Map',
                                style: TextStyle(
                                  color: isActuallyLive
                                      ? const Color(0xFF00E676)
                                      : Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                isActuallyLive
                                    ? Icons.radar_rounded
                                    : Icons.open_in_new_rounded,
                                size: 11,
                                color: isActuallyLive
                                    ? const Color(0xFF00E676)
                                    : Colors.white70,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // Bottom Info Row & Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titleText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            statusSubtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActuallyLive
                                  ? const Color(0xFF00E676)
                                  : Colors.white.withValues(alpha: 0.65),
                              fontSize: 11.5,
                              fontWeight: isActuallyLive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: Icon(
                        Icons.directions_rounded,
                        color: isActuallyLive
                            ? const Color(0xFF00E676)
                            : tabColor,
                        size: 22,
                      ),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: isLiveType ? 'View Live Map' : 'Directions & Map',
                      onPressed: () => _handleLocationTap(lat, lng, data),
                    ),
                  ],
                ),

                // Stop Sharing Button (Only visible to sender while sharing is active)
                if (widget.isMe &&
                    isActuallyLive &&
                    widget.messageId != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: OutlinedButton.icon(
                      icon: const Icon(
                        Icons.stop_circle_outlined,
                        size: 15,
                        color: Color(0xFFFF5252),
                      ),
                      label: const Text(
                        'Stop Sharing',
                        style: TextStyle(
                          color: Color(0xFFFF5252),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Color(0xFFFF5252),
                          width: 0.9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: _handleStopSharing,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
