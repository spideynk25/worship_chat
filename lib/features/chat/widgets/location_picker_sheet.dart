import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/location_service.dart';

enum LocationShareType { current, live }

class LocationResult {
  final LocationShareType type;
  final double latitude;
  final double longitude;
  final Duration? duration;
  final double? accuracy;

  LocationResult({
    required this.type,
    required this.latitude,
    required this.longitude,
    this.duration,
    this.accuracy,
  });
}

class LocationPickerSheet extends StatefulWidget {
  const LocationPickerSheet({super.key});

  static Future<LocationResult?> show(BuildContext context) {
    return showModalBottomSheet<LocationResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const LocationPickerSheet(),
    );
  }

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  Position? _currentPosition;
  bool _isLoading = true;
  String? _errorMessage;
  Duration _selectedLiveDuration = const Duration(hours: 1);
  bool _showDurationSelector = false;

  @override
  void initState() {
    super.initState();
    _fetchPosition();
  }

  Future<void> _fetchPosition() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final pos = await LocationService.instance.getCurrentLocation();
      if (!mounted) return;
      if (pos != null) {
        setState(() {
          _currentPosition = pos;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Location permission or GPS is unavailable';
        });
      }
    } catch (e) {
      log('Error in LocationPickerSheet: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not get location: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161524),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle pill
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.location_on_rounded, color: Color(0xFF00E676), size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Share Location',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, size: 18, color: greyColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Column(
                children: [
                  const CircularProgressIndicator(color: tabColor, strokeWidth: 2.5),
                  const SizedBox(height: 14),
                  Text(
                    'Acquiring GPS location...',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                  ),
                ],
              ),
            )
          else if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  const Icon(Icons.location_off_rounded, color: Colors.orange, size: 36),
                  const SizedBox(height: 10),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: _fetchPosition,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tabColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Retry GPS', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            )
          else ...[
            // Option 1: Share Live Location
            _buildOptionTile(
              icon: Icons.radar_rounded,
              iconColor: const Color(0xFF00E676),
              title: 'Share Live Location',
              subtitle: _showDurationSelector
                  ? 'Select duration below'
                  : 'Streams location updates in real-time',
              trailing: _showDurationSelector
                  ? const Icon(Icons.keyboard_arrow_up_rounded, color: greyColor)
                  : const Icon(Icons.keyboard_arrow_down_rounded, color: greyColor),
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _showDurationSelector = !_showDurationSelector);
              },
            ),

            if (_showDurationSelector) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Live sharing duration:',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _buildDurationChip(const Duration(minutes: 15), '15 mins'),
                        const SizedBox(width: 8),
                        _buildDurationChip(const Duration(hours: 1), '1 hour'),
                        const SizedBox(width: 8),
                        _buildDurationChip(const Duration(hours: 8), '8 hours'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                        label: const Text('Start Live Sharing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00B074),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          Navigator.pop(
                            context,
                            LocationResult(
                              type: LocationShareType.live,
                              latitude: _currentPosition!.latitude,
                              longitude: _currentPosition!.longitude,
                              duration: _selectedLiveDuration,
                              accuracy: _currentPosition!.accuracy,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),
            const Divider(color: dividerColor),
            const SizedBox(height: 10),

            // Option 2: Send Current Location
            _buildOptionTile(
              icon: Icons.my_location_rounded,
              iconColor: const Color(0xFF29B6F6),
              title: 'Send Your Current Location',
              subtitle: _currentPosition != null
                  ? 'Accurate to ${(_currentPosition!.accuracy).toInt()} meters'
                  : 'Fast static GPS snapshot',
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.pop(
                  context,
                  LocationResult(
                    type: LocationShareType.current,
                    latitude: _currentPosition!.latitude,
                    longitude: _currentPosition!.longitude,
                    accuracy: _currentPosition!.accuracy,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildDurationChip(Duration duration, String label) {
    final isSelected = _selectedLiveDuration == duration;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedLiveDuration = duration);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00B074) : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.transparent : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
