import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  static const String _prefSessionsKey = 'live_location_active_sessions';

  final Map<String, StreamSubscription<Position>> _activeLiveStreams = {};

  bool isTracking(String messageId) => _activeLiveStreams.containsKey(messageId);

  /// Configure platform-specific location settings to enable background & foreground service updates
  LocationSettings _createLiveLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // update every 5 meters moved
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 4),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "Live Location Sharing Active",
          notificationText: "Sharing real-time location with your contact",
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 5,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );
    }
  }

  /// Verify and request location service & permissions
  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      log('⚠️ Location services are disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        log('⚠️ Location permission denied by user');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      log('⚠️ Location permissions are permanently denied');
      return false;
    }

    return true;
  }

  /// Get current GPS coordinates
  Future<Position?> getCurrentLocation() async {
    final hasPerm = await checkAndRequestPermission();
    if (!hasPerm) return null;

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      log('Error getting current location: $e');
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  /// Open coordinates in open-source Maps without requiring any API key
  Future<void> openMapForCoordinates(double lat, double lng) async {
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    final osmUri = Uri.parse(
        'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=16/$lat/$lng');
    try {
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
        return;
      }
      if (await canLaunchUrl(osmUri)) {
        await launchUrl(osmUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      log('Error launching open-source map URL: $e');
    }
  }

  /// Push a real-time location coordinate update to Firestore for both sender and receiver
  Future<void> updateLiveLocationInFirestore({
    required String messageId,
    required String currentUserId,
    required String receiverId,
    required double latitude,
    required double longitude,
    required int liveUntil,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now > liveUntil) {
      log('⏱️ Live location duration expired for message $messageId');
      await stopLiveLocationSharing(
        messageId: messageId,
        currentUserId: currentUserId,
        receiverId: receiverId,
      );
      return;
    }

    final liveData = jsonEncode({
      'latitude': latitude,
      'longitude': longitude,
      'isLive': true,
      'liveUntil': liveUntil,
      'updatedAt': now,
      'sharerId': currentUserId,
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final senderMsgRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(receiverId)
          .collection('messages')
          .doc(messageId);
      final receiverMsgRef = FirebaseFirestore.instance
          .collection('users')
          .doc(receiverId)
          .collection('chats')
          .doc(currentUserId)
          .collection('messages')
          .doc(messageId);

      batch.update(senderMsgRef, {'fileMessageData': liveData});
      batch.update(receiverMsgRef, {'fileMessageData': liveData});
      await batch.commit();
      log('📍 Live location updated in Firestore: ($latitude, $longitude)');
    } catch (e) {
      log('❌ Error updating live location in Firestore: $e');
    }
  }

  /// Start streaming live location updates to 1-to-1 Firestore chat documents
  /// Uses foreground service configuration so tracking persists when navigating away or going background
  Future<void> startLiveLocationTracking({
    required String messageId,
    required String currentUserId,
    required String receiverId,
    required Duration duration,
    int? explicitLiveUntil,
  }) async {
    final hasPerm = await checkAndRequestPermission();
    if (!hasPerm) return;

    // Cancel existing stream for same message if any
    _activeLiveStreams[messageId]?.cancel();

    final liveUntil = explicitLiveUntil ??
        DateTime.now().add(duration).millisecondsSinceEpoch;

    // Save session in SharedPreferences for background & resume persistence
    await _saveActiveSession(
      messageId: messageId,
      currentUserId: currentUserId,
      receiverId: receiverId,
      liveUntil: liveUntil,
    );

    // 1. Immediately push the current position without waiting for physical movement
    try {
      final currentPos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await updateLiveLocationInFirestore(
        messageId: messageId,
        currentUserId: currentUserId,
        receiverId: receiverId,
        latitude: currentPos.latitude,
        longitude: currentPos.longitude,
        liveUntil: liveUntil,
      );
    } catch (e) {
      log('⚠️ Could not send initial live location immediately: $e');
    }

    // 2. Start continuous streaming using platform background/foreground settings
    final locationSettings = _createLiveLocationSettings();

    final sub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) async {
        await updateLiveLocationInFirestore(
          messageId: messageId,
          currentUserId: currentUserId,
          receiverId: receiverId,
          latitude: position.latitude,
          longitude: position.longitude,
          liveUntil: liveUntil,
        );
      },
      onError: (e) {
        log('Error in live location position stream: $e');
      },
    );

    _activeLiveStreams[messageId] = sub;
  }

  /// Stop streaming live location and mark isLive: false in Firestore
  Future<void> stopLiveLocationSharing({
    required String messageId,
    required String currentUserId,
    required String receiverId,
  }) async {
    _activeLiveStreams[messageId]?.cancel();
    _activeLiveStreams.remove(messageId);

    await _removeActiveSession(messageId);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(receiverId)
          .collection('messages')
          .doc(messageId)
          .get();

      if (doc.exists && doc.data() != null) {
        final existingRaw = doc.data()!['fileMessageData'] as String?;
        if (existingRaw != null && existingRaw.isNotEmpty) {
          final map =
              Map<String, dynamic>.from(jsonDecode(existingRaw) as Map);
          map['isLive'] = false;
          final updatedJson = jsonEncode(map);

          final batch = FirebaseFirestore.instance.batch();
          final senderMsgRef = FirebaseFirestore.instance
              .collection('users')
              .doc(currentUserId)
              .collection('chats')
              .doc(receiverId)
              .collection('messages')
              .doc(messageId);
          final receiverMsgRef = FirebaseFirestore.instance
              .collection('users')
              .doc(receiverId)
              .collection('chats')
              .doc(currentUserId)
              .collection('messages')
              .doc(messageId);

          batch.update(senderMsgRef, {'fileMessageData': updatedJson});
          batch.update(receiverMsgRef, {'fileMessageData': updatedJson});
          await batch.commit();
          log('🛑 Stopped live location sharing for message $messageId');
        }
      }
    } catch (e) {
      log('Error stopping live location: $e');
    }
  }

  /// Resumes any active live location tracking sessions across app resumes or page navigations
  Future<void> resumeActiveLiveLocationTracking() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_prefSessionsKey);
      if (rawList == null || rawList.isEmpty) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final updatedList = <String>[];

      for (final jsonStr in rawList) {
        try {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          final messageId = map['messageId'] as String;
          final currentUserId = map['currentUserId'] as String;
          final receiverId = map['receiverId'] as String;
          final liveUntil = map['liveUntil'] as int;

          if (now < liveUntil) {
            updatedList.add(jsonStr);
            if (!_activeLiveStreams.containsKey(messageId)) {
              final remainingDuration =
                  Duration(milliseconds: liveUntil - now);
              log('🔄 Resuming active live location tracking for $messageId ($remainingDuration remaining)');
              startLiveLocationTracking(
                messageId: messageId,
                currentUserId: currentUserId,
                receiverId: receiverId,
                duration: remainingDuration,
                explicitLiveUntil: liveUntil,
              );
            }
          } else {
            log('⏱️ Session expired while app was away: $messageId');
            stopLiveLocationSharing(
              messageId: messageId,
              currentUserId: currentUserId,
              receiverId: receiverId,
            );
          }
        } catch (e) {
          log('Error parsing saved live session: $e');
        }
      }

      await prefs.setStringList(_prefSessionsKey, updatedList);
    } catch (e) {
      log('Error resuming live location tracking sessions: $e');
    }
  }

  Future<void> _saveActiveSession({
    required String messageId,
    required String currentUserId,
    required String receiverId,
    required int liveUntil,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefSessionsKey) ?? [];
      list.removeWhere((item) {
        try {
          final m = jsonDecode(item) as Map;
          return m['messageId'] == messageId;
        } catch (_) {
          return false;
        }
      });
      list.add(jsonEncode({
        'messageId': messageId,
        'currentUserId': currentUserId,
        'receiverId': receiverId,
        'liveUntil': liveUntil,
      }));
      await prefs.setStringList(_prefSessionsKey, list);
    } catch (e) {
      log('Error saving active live session: $e');
    }
  }

  Future<void> _removeActiveSession(String messageId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefSessionsKey) ?? [];
      list.removeWhere((item) {
        try {
          final m = jsonDecode(item) as Map;
          return m['messageId'] == messageId;
        } catch (_) {
          return false;
        }
      });
      await prefs.setStringList(_prefSessionsKey, list);
    } catch (e) {
      log('Error removing active live session: $e');
    }
  }

  /// Cancel all active live location streams (e.g. app dispose)
  void disposeAll() {
    for (final sub in _activeLiveStreams.values) {
      sub.cancel();
    }
    _activeLiveStreams.clear();
  }
}
