import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/location_service.dart';
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
  late AnimationController _pulseController;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    // Refresh countdown every 30 seconds for live location
    if (widget.messageType == 'live_location') {
      _countdownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(covariant LocationMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locationData != widget.locationData ||
        oldWidget.messageType != widget.messageType) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _countdownTimer?.cancel();
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
    // Open in-app OpenStreetMap screen directly with zero API key!
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LiveLocationScreen(
          messageId: widget.messageId,
          currentUserId: widget.currentUserId,
          receiverId: widget.receiverId,
          sharerId: data['sharerId']?.toString(),
          sharerName: widget.senderName ?? (widget.isMe ? 'You' : 'Shared Location'),
          sharerProfilePic: widget.senderProfilePic,
          initialLatitude: lat,
          initialLongitude: lng,
          isLive: widget.messageType == 'live_location' && (data['isLive'] == true),
          liveUntil: (data['liveUntil'] as num?)?.toInt(),
          updatedAt: (data['updatedAt'] as num?)?.toInt(),
          isMe: widget.isMe,
        ),
      ),
    );
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
    final bool isLiveType = widget.messageType == 'live_location';
    final int? liveUntil = (data['liveUntil'] as num?)?.toInt();
    final bool rawIsLive = data['isLive'] == true;
    final now = DateTime.now().millisecondsSinceEpoch;
    final bool isActuallyLive = isLiveType && rawIsLive && (liveUntil == null || liveUntil > now);

    String? statusSubtitle;
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
      } else {
        statusSubtitle = 'Live location ended';
      }
    } else {
      statusSubtitle = '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 230, maxWidth: 280),
      decoration: BoxDecoration(
        color: const Color(0xFF161524),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActuallyLive
              ? const Color(0xFF00E676).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Map Preview Area with OpenStreetMap or Simulated Grid
          GestureDetector(
            onTap: () => _handleLocationTap(lat, lng, data),
            child: SizedBox(
              height: 125,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Real OpenStreetMap background preview
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: FlutterMap(
                        key: ValueKey('osm_map_${widget.messageId ?? lat}_$lng'),
                        options: MapOptions(
                          initialCenter: LatLng(lat, lng),
                          initialZoom: 14.5,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.shadow.worshipchat',
                            maxZoom: 19,
                            tileBuilder: (context, tileWidget, tile) {
                              return ColorFiltered(
                                colorFilter: const ColorFilter.matrix(<double>[
                                  -0.80, 0,     0,     0, 245,
                                  0,     -0.80, 0,     0, 245,
                                  0,     0,     -0.78, 0, 250,
                                  0,     0,     0,     1, 0,
                                ]),
                                child: tileWidget,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Subtle dark gradient vignette overlay for readability
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.45),
                        ],
                      ),
                    ),
                  ),

                  // Center Pin with Radar / Pulse Effect
                  if (isActuallyLive) ...[
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 38 + (_pulseController.value * 24),
                          height: 38 + (_pulseController.value * 24),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF00E676).withValues(
                              alpha: 0.28 * (1.0 - _pulseController.value),
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
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E676).withValues(alpha: 0.45),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.radar_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isLiveType ? Colors.grey[700] : const Color(0xFFE53935),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        isLiveType ? Icons.location_off_rounded : Icons.location_on_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],

                  // Top Pill Overlay: Live indicator or Current Location
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActuallyLive
                              ? const Color(0xFF00E676).withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.15),
                          width: 0.6,
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
                              isLiveType ? Icons.timer_off_outlined : Icons.my_location_rounded,
                              color: isLiveType ? Colors.grey : const Color(0xFF29B6F6),
                              size: 11,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isLiveType ? 'ENDED' : 'CURRENT',
                              style: TextStyle(
                                color: isLiveType ? Colors.grey : const Color(0xFF29B6F6),
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

                  // Bottom Right: Tap hint
                  Positioned(
                    bottom: 6,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isLiveType
                              ? const Color(0xFF00E676).withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.15),
                          width: 0.6,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isLiveType ? 'Live Map' : 'Maps',
                            style: TextStyle(
                              color: isLiveType ? const Color(0xFF00E676) : Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            isLiveType ? Icons.radar_rounded : Icons.open_in_new_rounded,
                            size: 11,
                            color: isLiveType ? const Color(0xFF00E676) : Colors.white70,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
                            isLiveType ? 'Live Location' : 'Current Location',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            statusSubtitle,
                            style: TextStyle(
                              color: isActuallyLive
                                  ? const Color(0xFF00E676)
                                  : Colors.white.withValues(alpha: 0.6),
                              fontSize: 11.5,
                              fontWeight: isActuallyLive ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        isLiveType ? Icons.map_rounded : Icons.directions_rounded,
                        color: isLiveType ? const Color(0xFF00E676) : tabColor,
                        size: 22,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: isLiveType ? 'View Live Map' : 'Open in Maps',
                      onPressed: () => _handleLocationTap(lat, lng, data),
                    ),
                  ],
                ),

                // Stop Sharing Button (Only visible to sender while sharing is active)
                if (widget.isMe && isActuallyLive && widget.messageId != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.stop_circle_outlined, size: 15, color: Color(0xFFFF5252)),
                      label: const Text(
                        'Stop Sharing',
                        style: TextStyle(
                          color: Color(0xFFFF5252),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFF5252), width: 0.9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
