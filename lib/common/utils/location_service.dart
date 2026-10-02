import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  final Map<String, StreamSubscription<Position>> _activeLiveStreams = {};

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
    // 1. Try standard device geo: URI (opens default installed map app without any API key)
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    // 2. Open-source OpenStreetMap web fallback (100% free, no API key needed)
    final osmUri = Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=16/$lat/$lng');
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

  /// Start streaming live location updates to 1-to-1 Firestore chat documents
  void startLiveLocationTracking({
    required String messageId,
    required String currentUserId,
    required String receiverId,
    required Duration duration,
  }) {
    // Cancel existing stream for same message if any
    _activeLiveStreams[messageId]?.cancel();

    final liveUntil = DateTime.now().add(duration).millisecondsSinceEpoch;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // update when moved by 10 meters
    );

    final sub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) async {
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
          'latitude': position.latitude,
          'longitude': position.longitude,
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
          log('📍 Live location updated: (${position.latitude}, ${position.longitude})');
        } catch (e) {
          log('❌ Error updating live location in Firestore: $e');
        }
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
          final map = Map<String, dynamic>.from(jsonDecode(existingRaw) as Map);
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

  /// Cancel all active live location streams (e.g. app dispose)
  void disposeAll() {
    for (final sub in _activeLiveStreams.values) {
      sub.cancel();
    }
    _activeLiveStreams.clear();
  }
}
