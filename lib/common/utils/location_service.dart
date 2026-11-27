import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum LocationReadiness {
  ready,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
}

enum TravelMode {
  driving,
  walking,
  cycling,
}

extension TravelModeX on TravelMode {
  String get label {
    switch (this) {
      case TravelMode.driving:
        return 'Drive';
      case TravelMode.walking:
        return 'Walk';
      case TravelMode.cycling:
        return 'Cycle';
    }
  }

  String get osmRoutingFolder {
    switch (this) {
      case TravelMode.driving:
        return 'routed-car';
      case TravelMode.walking:
        return 'routed-foot';
      case TravelMode.cycling:
        return 'routed-bike';
    }
  }

  double get fallbackSpeedMetersPerSecond {
    switch (this) {
      case TravelMode.driving:
        return 35000 / 3600;
      case TravelMode.walking:
        return 4800 / 3600;
      case TravelMode.cycling:
        return 15000 / 3600;
    }
  }
}

class PlaceSearchResult {
  final String name;
  final String subtitle;
  final double latitude;
  final double longitude;
  final String? category;

  const PlaceSearchResult({
    required this.name,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
    this.category,
  });

  LatLng get latLng => LatLng(latitude, longitude);
}

class ReverseGeocodeResult {
  final String? placeName;
  final String address;

  const ReverseGeocodeResult({
    this.placeName,
    required this.address,
  });
}

class RouteStep {
  final String instruction;
  final String streetName;
  final String maneuverType;
  final String? maneuverModifier;
  final double distanceMeters;
  final double durationSeconds;
  final LatLng location;

  const RouteStep({
    required this.instruction,
    required this.streetName,
    required this.maneuverType,
    this.maneuverModifier,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.location,
  });
}

class MapRouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteStep> steps;
  final TravelMode mode;
  final bool isFallbackEstimate;

  const MapRouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.steps = const [],
    required this.mode,
    this.isFallbackEstimate = false,
  });
}

class _SentTrackPoint {
  final double latitude;
  final double longitude;
  final int timestampMs;

  const _SentTrackPoint(this.latitude, this.longitude, this.timestampMs);
}

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  static const String _prefSessionsKey = 'live_location_active_sessions';
  static const String _userAgent =
      'WorshipChat/1.0 (https://github.com/worshipchat)';

  final Map<String, StreamSubscription<Position>> _activeLiveStreams = {};
  final Map<String, _SentTrackPoint> _lastSentPoints = {};
  final ValueNotifier<Position?> latestPositionNotifier = ValueNotifier(null);

  final Map<String, ReverseGeocodeResult> _reverseCache = {};

  final Dio _http = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
      headers: const {'User-Agent': _userAgent},
    ),
  );

  bool isTracking(String messageId) => _activeLiveStreams.containsKey(messageId);

  /// Uses Android Fused Location Provider (`forceLocationManager: false`) so
  /// indoor Wi-Fi + cell + GNSS locks work reliably like Google Maps.
  LocationSettings _createLiveLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 4,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 3),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Live Location Sharing Active',
          notificationText: 'Sharing real-time location in Worship Chat',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.fitness,
        distanceFilter: 4,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 4,
      );
    }
  }

  Future<LocationReadiness> checkLocationReadiness({
    bool requestPermission = true,
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        log('⚠️ Location services are disabled');
        return LocationReadiness.serviceDisabled;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        log('⚠️ Location permission denied by user');
        return LocationReadiness.permissionDenied;
      }

      if (permission == LocationPermission.deniedForever) {
        log('⚠️ Location permissions are permanently denied');
        return LocationReadiness.permissionDeniedForever;
      }

      return LocationReadiness.ready;
    } catch (e) {
      log('Error checking location readiness: $e');
      return LocationReadiness.serviceDisabled;
    }
  }

  /// Verify and request location service & permissions
  Future<bool> checkAndRequestPermission() async {
    return (await checkLocationReadiness(requestPermission: true)) ==
        LocationReadiness.ready;
  }

  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (_) {
      return false;
    }
  }

  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  /// Immediately returns last known OS position (if any) so map UIs render
  /// without waiting 5-15s for a fresh cold GPS lock.
  Future<Position?> getFastInitialPosition() async {
    if (latestPositionNotifier.value != null) {
      return latestPositionNotifier.value;
    }
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        latestPositionNotifier.value = last;
        return last;
      }
    } catch (_) {}
    return null;
  }

  /// Get current GPS coordinates (prefers Fused Location, falls back to last known).
  Future<Position?> getCurrentLocation() async {
    final hasPerm = await checkAndRequestPermission();
    if (!hasPerm) return null;

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: defaultTargetPlatform == TargetPlatform.android
            ? AndroidSettings(
                accuracy: LocationAccuracy.high,
                forceLocationManager: false,
                timeLimit: const Duration(seconds: 12),
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 12),
              ),
      );
      latestPositionNotifier.value = pos;
      return pos;
    } catch (e) {
      log('Error getting current location: $e');
      try {
        final fallback = await Geolocator.getLastKnownPosition();
        if (fallback != null) {
          latestPositionNotifier.value = fallback;
        }
        return fallback;
      } catch (_) {
        return null;
      }
    }
  }

  /// Open coordinates in native Maps / Google Maps or OpenStreetMap web.
  Future<void> openMapForCoordinates(
    double lat,
    double lng, {
    String? label,
  }) async {
    final encodedLabel =
        label != null && label.trim().isNotEmpty ? Uri.encodeComponent(label) : null;
    final geoUri = Uri.parse(
      encodedLabel != null
          ? 'geo:$lat,$lng?q=$lat,$lng($encodedLabel)'
          : 'geo:$lat,$lng?q=$lat,$lng',
    );
    final googleMapsUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    final osmUri = Uri.parse(
      'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=16/$lat/$lng',
    );
    try {
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
        return;
      }
      if (await canLaunchUrl(googleMapsUri)) {
        await launchUrl(googleMapsUri, mode: LaunchMode.externalApplication);
        return;
      }
      if (await canLaunchUrl(osmUri)) {
        await launchUrl(osmUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      log('Error launching map URL: $e');
    }
  }

  /// Open turn-by-turn external navigation if requested by user.
  Future<void> openExternalDirections(
    double destLat,
    double destLng, {
    TravelMode mode = TravelMode.driving,
  }) async {
    final gmapMode = switch (mode) {
      TravelMode.driving => 'driving',
      TravelMode.walking => 'walking',
      TravelMode.cycling => 'bicycling',
    };
    final navUri = Uri.parse(
      'google.navigation:q=$destLat,$destLng&mode=${gmapMode[0]}',
    );
    final webDirUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng&travelmode=$gmapMode',
    );
    try {
      if (await canLaunchUrl(navUri)) {
        await launchUrl(navUri, mode: LaunchMode.externalApplication);
        return;
      }
      if (await canLaunchUrl(webDirUri)) {
        await launchUrl(webDirUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      log('Error launching external directions: $e');
    }
  }

  /// Parse free-form text or coordinates for Google-Maps-like place search.
  Future<List<PlaceSearchResult>> searchPlaces(
    String query, {
    double? biasLat,
    double? biasLng,
    CancelToken? cancelToken,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    // Direct coordinate entry support (e.g. "12.9716, 77.5946")
    final coordMatch = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$',
    ).firstMatch(trimmed);
    if (coordMatch != null) {
      final lat = double.tryParse(coordMatch.group(1)!);
      final lng = double.tryParse(coordMatch.group(2)!);
      if (lat != null &&
          lng != null &&
          lat >= -90 &&
          lat <= 90 &&
          lng >= -180 &&
          lng <= 180) {
        return [
          PlaceSearchResult(
            name: 'Pinned Coordinates',
            subtitle: '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
            latitude: lat,
            longitude: lng,
            category: 'coordinates',
          ),
        ];
      }
    }

    try {
      final response = await _http.get(
        'https://photon.komoot.io/api/',
        cancelToken: cancelToken,
        queryParameters: {
          'q': trimmed,
          'limit': 7,
          if (biasLat != null && biasLng != null) 'lat': biasLat,
          if (biasLat != null && biasLng != null) 'lon': biasLng,
        },
      );
      if (response.statusCode == 200 && response.data is Map) {
        final parsed = parsePhotonSearchResponse(
          Map<String, dynamic>.from(response.data as Map),
        );
        if (parsed.isNotEmpty) return parsed;
      }
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) rethrow;
      log('Photon place search failed, falling back to Nominatim: $e');
    }

    try {
      final response = await _http.get(
        'https://nominatim.openstreetmap.org/search',
        cancelToken: cancelToken,
        queryParameters: {
          'q': trimmed,
          'format': 'jsonv2',
          'addressdetails': 1,
          'limit': 7,
        },
      );
      if (response.statusCode == 200 && response.data is List) {
        return parseNominatimSearchResponse(response.data as List);
      }
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) rethrow;
      log('Nominatim place search error: $e');
    }

    return const [];
  }

  /// Reverse geocode coordinates with ~25m rounding cache.
  Future<ReverseGeocodeResult?> reverseGeocode(
    double lat,
    double lng, {
    CancelToken? cancelToken,
  }) async {
    final cacheKey = '${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}';
    final cached = _reverseCache[cacheKey];
    if (cached != null) return cached;

    try {
      final response = await _http.get(
        'https://nominatim.openstreetmap.org/reverse',
        cancelToken: cancelToken,
        queryParameters: {
          'format': 'json',
          'lat': lat,
          'lon': lng,
          'zoom': 18,
          'addressdetails': 1,
        },
      );
      if (response.statusCode == 200 && response.data is Map) {
        final result = parseNominatimReverseResponse(
          Map<String, dynamic>.from(response.data as Map),
        );
        if (result != null) {
          if (_reverseCache.length > 64) _reverseCache.clear();
          _reverseCache[cacheKey] = result;
          return result;
        }
      }
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) rethrow;
    }

    try {
      final response = await _http.get(
        'https://photon.komoot.io/reverse',
        cancelToken: cancelToken,
        queryParameters: {'lat': lat, 'lon': lng},
      );
      if (response.statusCode == 200 && response.data is Map) {
        final items = parsePhotonSearchResponse(
          Map<String, dynamic>.from(response.data as Map),
        );
        if (items.isNotEmpty) {
          final first = items.first;
          final result = ReverseGeocodeResult(
            placeName: first.name,
            address: first.subtitle.isNotEmpty
                ? '${first.name}, ${first.subtitle}'
                : first.name,
          );
          if (_reverseCache.length > 64) _reverseCache.clear();
          _reverseCache[cacheKey] = result;
          return result;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Fetch real road / pedestrian / cycle routes with turn-by-turn steps.
  Future<MapRouteResult> fetchRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    TravelMode mode = TravelMode.driving,
    CancelToken? cancelToken,
  }) async {
    final coords = '$startLng,$startLat;$endLng,$endLat';
    final primaryUrl =
        'https://routing.openstreetmap.de/${mode.osmRoutingFolder}/route/v1/driving/$coords?overview=full&geometries=geojson&steps=true';

    try {
      final response = await _http.get(primaryUrl, cancelToken: cancelToken);
      if (response.statusCode == 200 && response.data is Map) {
        final parsed = parseOsrmRouteResponse(
          Map<String, dynamic>.from(response.data as Map),
          mode: mode,
        );
        if (parsed != null) return parsed;
      }
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) rethrow;
      log('Primary OSRM ($mode) failed: $e');
    }

    if (mode == TravelMode.driving) {
      try {
        final fallbackUrl =
            'https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson&steps=true';
        final response = await _http.get(fallbackUrl, cancelToken: cancelToken);
        if (response.statusCode == 200 && response.data is Map) {
          final parsed = parseOsrmRouteResponse(
            Map<String, dynamic>.from(response.data as Map),
            mode: mode,
          );
          if (parsed != null) return parsed;
        }
      } catch (e) {
        if (e is DioException && CancelToken.isCancel(e)) rethrow;
      }
    }

    final start = LatLng(startLat, startLng);
    final end = LatLng(endLat, endLng);
    final directDistance = const Distance().as(LengthUnit.Meter, start, end);
    final estSeconds =
        (directDistance / mode.fallbackSpeedMetersPerSecond).roundToDouble();

    return MapRouteResult(
      points: [start, end],
      distanceMeters: directDistance,
      durationSeconds: estSeconds,
      steps: [
        RouteStep(
          instruction: 'Head directly toward destination',
          streetName: '',
          maneuverType: 'depart',
          distanceMeters: directDistance,
          durationSeconds: estSeconds,
          location: start,
        ),
      ],
      mode: mode,
      isFallbackEstimate: true,
    );
  }

  @visibleForTesting
  static List<PlaceSearchResult> parsePhotonSearchResponse(
    Map<String, dynamic> data,
  ) {
    final features = data['features'];
    if (features is! List) return const [];
    final results = <PlaceSearchResult>[];
    final seen = <String>{};

    for (final rawFeature in features) {
      if (rawFeature is! Map) continue;
      final feature = Map<String, dynamic>.from(rawFeature);
      final geometry = feature['geometry'];
      final properties = feature['properties'];
      if (geometry is! Map || properties is! Map) continue;
      final coords = geometry['coordinates'];
      if (coords is! List || coords.length < 2) continue;

      final lng = (coords[0] as num?)?.toDouble();
      final lat = (coords[1] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final props = Map<String, dynamic>.from(properties);
      final primary = (props['name'] as String?)?.trim();
      final streetParts = [
        if ((props['housenumber'] as String?)?.isNotEmpty == true)
          props['housenumber'].toString().trim(),
        if ((props['street'] as String?)?.isNotEmpty == true)
          props['street'].toString().trim(),
      ].join(' ');
      final subtitleParts = <String>[
        if (streetParts.isNotEmpty && streetParts != primary) streetParts,
        if ((props['locality'] as String?)?.isNotEmpty == true)
          props['locality'].toString().trim(),
        if ((props['district'] as String?)?.isNotEmpty == true &&
            props['district'] != props['city'])
          props['district'].toString().trim(),
        if ((props['city'] as String?)?.isNotEmpty == true)
          props['city'].toString().trim(),
        if ((props['state'] as String?)?.isNotEmpty == true)
          props['state'].toString().trim(),
        if ((props['country'] as String?)?.isNotEmpty == true)
          props['country'].toString().trim(),
      ];

      final name = (primary != null && primary.isNotEmpty)
          ? primary
          : (subtitleParts.isNotEmpty
              ? subtitleParts.first
              : '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}');
      final filteredSub = subtitleParts.where((p) => p != name).toList();
      final subtitle = filteredSub.join(', ');
      final dedupeKey = '$name|$subtitle'.toLowerCase();
      if (!seen.add(dedupeKey)) continue;

      results.add(
        PlaceSearchResult(
          name: name,
          subtitle: subtitle,
          latitude: lat,
          longitude: lng,
          category: (props['osm_value'] ?? props['type'])?.toString(),
        ),
      );
    }
    return results;
  }

  @visibleForTesting
  static List<PlaceSearchResult> parseNominatimSearchResponse(List<dynamic> data) {
    final results = <PlaceSearchResult>[];
    for (final item in data) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final lat = double.tryParse(map['lat']?.toString() ?? '');
      final lng = double.tryParse(map['lon']?.toString() ?? '');
      if (lat == null || lng == null) continue;
      final display = map['display_name']?.toString() ?? '';
      final nameProp = map['name']?.toString().trim();
      final parts = display
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final name = (nameProp != null && nameProp.isNotEmpty)
          ? nameProp
          : (parts.isNotEmpty ? parts.first : '$lat, $lng');
      final subtitle = parts.where((p) => p != name).take(3).join(', ');
      results.add(
        PlaceSearchResult(
          name: name,
          subtitle: subtitle,
          latitude: lat,
          longitude: lng,
          category: map['type']?.toString(),
        ),
      );
    }
    return results;
  }

  @visibleForTesting
  static ReverseGeocodeResult? parseNominatimReverseResponse(
    Map<String, dynamic> data,
  ) {
    final displayName = (data['display_name'] as String?)?.trim();
    final rawAddr = data['address'];
    if (rawAddr is Map) {
      final addr = Map<String, dynamic>.from(rawAddr);
      final poi = (data['name'] as String?)?.trim();
      final road = (addr['road'] ??
              addr['pedestrian'] ??
              addr['footway'] ??
              addr['neighbourhood'] ??
              addr['suburb'])
          ?.toString()
          .trim();
      final area = (addr['suburb'] ??
              addr['neighbourhood'] ??
              addr['city_district'])
          ?.toString()
          .trim();
      final city =
          (addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['county'])
              ?.toString()
              .trim();
      final state = addr['state']?.toString().trim();

      final parts = <String>[
        if (poi != null && poi.isNotEmpty) poi,
        if (road != null && road.isNotEmpty && road != poi) road,
        if (area != null && area.isNotEmpty && area != road && area != poi) area,
        if (city != null && city.isNotEmpty && city != area) city,
        if (state != null && state.isNotEmpty && state != city) state,
      ];
      if (parts.isNotEmpty) {
        return ReverseGeocodeResult(
          placeName: (poi != null && poi.isNotEmpty) ? poi : road,
          address: parts.join(', '),
        );
      }
    }
    if (displayName != null && displayName.isNotEmpty) {
      final short = displayName.split(',').take(3).map((e) => e.trim()).join(', ');
      return ReverseGeocodeResult(
        placeName: null,
        address: short,
      );
    }
    return null;
  }

  @visibleForTesting
  static MapRouteResult? parseOsrmRouteResponse(
    Map<String, dynamic> data, {
    required TravelMode mode,
  }) {
    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) return null;
    final firstRoute = Map<String, dynamic>.from(routes.first as Map);
    final geometry = firstRoute['geometry'] as Map?;
    final coords = geometry?['coordinates'] as List?;
    if (coords == null || coords.isEmpty) return null;

    final points = <LatLng>[];
    for (final c in coords) {
      if (c is List && c.length >= 2) {
        final lng = (c[0] as num?)?.toDouble();
        final lat = (c[1] as num?)?.toDouble();
        if (lat != null && lng != null) {
          points.add(LatLng(lat, lng));
        }
      }
    }
    if (points.isEmpty) return null;

    final distance = (firstRoute['distance'] as num?)?.toDouble() ?? 0.0;
    final duration = (firstRoute['duration'] as num?)?.toDouble() ?? 0.0;

    final parsedSteps = <RouteStep>[];
    final legs = firstRoute['legs'];
    if (legs is List) {
      for (final leg in legs) {
        if (leg is! Map) continue;
        final steps = leg['steps'];
        if (steps is! List) continue;
        for (final rawStep in steps) {
          if (rawStep is! Map) continue;
          final step = Map<String, dynamic>.from(rawStep);
          final maneuver = step['maneuver'] is Map
              ? Map<String, dynamic>.from(step['maneuver'] as Map)
              : <String, dynamic>{};
          final mType = (maneuver['type'] as String?) ?? 'continue';
          final mMod = maneuver['modifier'] as String?;
          final street = ((step['name'] as String?) ?? '').trim();
          final sDist = (step['distance'] as num?)?.toDouble() ?? 0.0;
          final sDur = (step['duration'] as num?)?.toDouble() ?? 0.0;
          final locList = maneuver['location'] as List?;
          final loc = (locList != null && locList.length >= 2)
              ? LatLng(
                  (locList[1] as num).toDouble(),
                  (locList[0] as num).toDouble(),
                )
              : points.first;

          parsedSteps.add(
            RouteStep(
              instruction: _formatManeuverInstruction(
                type: mType,
                modifier: mMod,
                streetName: street,
                exit: (maneuver['exit'] as num?)?.toInt(),
              ),
              streetName: street,
              maneuverType: mType,
              maneuverModifier: mMod,
              distanceMeters: sDist,
              durationSeconds: sDur,
              location: loc,
            ),
          );
        }
      }
    }

    return MapRouteResult(
      points: points,
      distanceMeters: distance,
      durationSeconds: duration,
      steps: parsedSteps,
      mode: mode,
    );
  }

  static String _formatManeuverInstruction({
    required String type,
    String? modifier,
    required String streetName,
    int? exit,
  }) {
    final onStreet = streetName.isNotEmpty ? ' onto $streetName' : '';
    final modText = (modifier ?? '').replaceAll('-', ' ').trim();

    switch (type) {
      case 'depart':
        return streetName.isNotEmpty
            ? 'Head toward $streetName'
            : 'Start your route';
      case 'arrive':
        return 'Arrive at your destination';
      case 'turn':
      case 'end of road':
      case 'new name':
        if (modText.contains('uturn')) return 'Make a U-turn$onStreet';
        if (modText.isNotEmpty) {
          return type == 'new name'
              ? 'Continue $modText$onStreet'
              : 'Turn $modText$onStreet';
        }
        return 'Continue$onStreet';
      case 'merge':
        return 'Merge ${modText.isNotEmpty ? modText : ''}$onStreet'.trim();
      case 'on ramp':
      case 'off ramp':
        return '${type == 'on ramp' ? 'Take ramp' : 'Take exit'}${modText.isNotEmpty ? ' $modText' : ''}$onStreet';
      case 'fork':
        return 'Keep ${modText.isNotEmpty ? modText : 'straight'} at fork$onStreet';
      case 'roundabout':
      case 'rotary':
      case 'exit roundabout':
        return exit != null
            ? 'At the roundabout, take exit $exit$onStreet'
            : 'Enter the roundabout$onStreet';
      default:
        return streetName.isNotEmpty ? 'Continue along $streetName' : 'Continue straight';
    }
  }

  /// Push a real-time location coordinate update to Firestore for both sender and receiver.
  Future<void> updateLiveLocationInFirestore({
    required String messageId,
    required String currentUserId,
    required String receiverId,
    required double latitude,
    required double longitude,
    required int liveUntil,
    double? heading,
    double? speed,
    double? accuracy,
    bool force = false,
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

    // Deduplicate identical stationary writes while still emitting heartbeats every 20s
    final prev = _lastSentPoints[messageId];
    if (!force && prev != null) {
      final moved = const Distance().as(
        LengthUnit.Meter,
        LatLng(prev.latitude, prev.longitude),
        LatLng(latitude, longitude),
      );
      final elapsedMs = now - prev.timestampMs;
      if (moved < 2.0 && elapsedMs < 20000) {
        return;
      }
    }
    _lastSentPoints[messageId] = _SentTrackPoint(latitude, longitude, now);

    final validHeading =
        (heading != null && heading.isFinite && heading >= 0) ? heading : null;
    final validSpeed =
        (speed != null && speed.isFinite && speed >= 0) ? speed : null;
    final validAccuracy =
        (accuracy != null && accuracy.isFinite && accuracy >= 0)
            ? accuracy
            : null;

    final liveData = jsonEncode({
      'latitude': latitude,
      'longitude': longitude,
      'isLive': true,
      'liveUntil': liveUntil,
      'updatedAt': now,
      'sharerId': currentUserId,
      if (validHeading != null) 'heading': validHeading,
      if (validSpeed != null) 'speed': validSpeed,
      if (validAccuracy != null) 'accuracy': validAccuracy,
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

  /// Start streaming live location updates to 1-to-1 Firestore chat documents.
  /// Uses Fused Location + foreground service notification for background durability.
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
    await _activeLiveStreams[messageId]?.cancel();
    _lastSentPoints.remove(messageId);

    final liveUntil =
        explicitLiveUntil ?? DateTime.now().add(duration).millisecondsSinceEpoch;

    await _saveActiveSession(
      messageId: messageId,
      currentUserId: currentUserId,
      receiverId: receiverId,
      liveUntil: liveUntil,
    );

    // 1. Immediately push last-known or fresh GPS coordinate without delay
    try {
      final currentPos = await getCurrentLocation();
      if (currentPos != null) {
        await updateLiveLocationInFirestore(
          messageId: messageId,
          currentUserId: currentUserId,
          receiverId: receiverId,
          latitude: currentPos.latitude,
          longitude: currentPos.longitude,
          liveUntil: liveUntil,
          heading: currentPos.heading,
          speed: currentPos.speed,
          accuracy: currentPos.accuracy,
          force: true,
        );
      }
    } catch (e) {
      log('⚠️ Could not send initial live location immediately: $e');
    }

    // 2. Start continuous streaming using Fused Location + background notification
    final locationSettings = _createLiveLocationSettings();

    final sub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) async {
        latestPositionNotifier.value = position;
        await updateLiveLocationInFirestore(
          messageId: messageId,
          currentUserId: currentUserId,
          receiverId: receiverId,
          latitude: position.latitude,
          longitude: position.longitude,
          liveUntil: liveUntil,
          heading: position.heading,
          speed: position.speed,
          accuracy: position.accuracy,
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
    await _activeLiveStreams[messageId]?.cancel();
    _activeLiveStreams.remove(messageId);
    _lastSentPoints.remove(messageId);

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
          map['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
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
              final remainingDuration = Duration(milliseconds: liveUntil - now);
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
    _lastSentPoints.clear();
  }
}
