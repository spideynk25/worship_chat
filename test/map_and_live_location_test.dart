import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/common/utils/location_service.dart';
import 'package:worship_chat/common/utils/map_style_config.dart';
import 'package:worship_chat/features/chat/screens/live_location_screen.dart';
import 'package:worship_chat/features/chat/widgets/location_message_widget.dart';
import 'package:worship_chat/features/chat/widgets/location_picker_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MapStyleRegistry.styleNotifier.value = AppMapStyle.street;
  });

  group('MapStyleRegistry & Tile Configuration', () {
    test('all styles have valid HTTPS templates and persist cleanly', () async {
      for (final style in AppMapStyle.values) {
        final spec = MapStyleRegistry.specFor(style);
        expect(spec.urlTemplate, startsWith('https://'));
        expect(spec.maxNativeZoom, greaterThanOrEqualTo(17));
        if (style == AppMapStyle.hybrid) {
          expect(spec.labelOverlayTemplate, isNotNull);
          expect(spec.labelOverlayTemplate, startsWith('https://'));
        }
      }

      await MapStyleRegistry.saveStyle(AppMapStyle.hybrid);
      MapStyleRegistry.styleNotifier.value = AppMapStyle.street;
      final reloaded = await MapStyleRegistry.loadSavedStyle();
      expect(reloaded, AppMapStyle.hybrid);
      expect(MapStyleRegistry.styleNotifier.value, AppMapStyle.hybrid);
    });
  });

  group('LocationService Search, Geocoding & Routing Parsers', () {
    test('searchPlaces parses raw coordinates offline', () async {
      final results = await LocationService.instance.searchPlaces('12.9716, 77.5946');
      expect(results, hasLength(1));
      expect(results.first.name, 'Pinned Coordinates');
      expect(results.first.latitude, closeTo(12.9716, 0.0001));
      expect(results.first.longitude, closeTo(77.5946, 0.0001));
    });

    test('parsePhotonSearchResponse extracts clean deduplicated places', () {
      final parsed = LocationService.parsePhotonSearchResponse({
        'features': [
          {
            'geometry': {
              'coordinates': [77.5946, 12.9716],
            },
            'properties': {
              'name': 'Cubbon Park',
              'street': 'Kasturba Road',
              'city': 'Bengaluru',
              'state': 'Karnataka',
              'country': 'India',
              'osm_value': 'park',
            },
          },
          {
            'geometry': {
              'coordinates': [77.5946, 12.9716],
            },
            'properties': {
              'name': 'Cubbon Park',
              'street': 'Kasturba Road',
              'city': 'Bengaluru',
              'state': 'Karnataka',
              'country': 'India',
            },
          },
        ],
      });

      expect(parsed, hasLength(1));
      expect(parsed.first.name, 'Cubbon Park');
      expect(parsed.first.subtitle, 'Kasturba Road, Bengaluru, Karnataka, India');
      expect(parsed.first.category, 'park');
    });

    test('parseNominatimReverseResponse builds concise place and address', () {
      final result = LocationService.parseNominatimReverseResponse({
        'name': 'ISKCON Temple',
        'display_name': 'ISKCON Temple, Chord Road, Rajajinagar, Bengaluru, India',
        'address': {
          'road': 'Chord Road',
          'suburb': 'Rajajinagar',
          'city': 'Bengaluru',
          'state': 'Karnataka',
        },
      });

      expect(result, isNotNull);
      expect(result!.placeName, 'ISKCON Temple');
      expect(
        result.address,
        'ISKCON Temple, Chord Road, Rajajinagar, Bengaluru, Karnataka',
      );
    });

    test('parseOsrmRouteResponse parses polyline geometry and turn-by-turn steps', () {
      final route = LocationService.parseOsrmRouteResponse(
        {
          'routes': [
            {
              'distance': 1850.5,
              'duration': 240.0,
              'geometry': {
                'coordinates': [
                  [77.5946, 12.9716],
                  [77.6000, 12.9750],
                  [77.6100, 12.9800],
                ],
              },
              'legs': [
                {
                  'steps': [
                    {
                      'name': 'MG Road',
                      'distance': 850.0,
                      'duration': 90.0,
                      'maneuver': {
                        'type': 'depart',
                        'location': [77.5946, 12.9716],
                      },
                    },
                    {
                      'name': 'Brigade Road',
                      'distance': 600.0,
                      'duration': 85.0,
                      'maneuver': {
                        'type': 'turn',
                        'modifier': 'right',
                        'location': [77.6000, 12.9750],
                      },
                    },
                    {
                      'name': '',
                      'distance': 400.5,
                      'duration': 65.0,
                      'maneuver': {
                        'type': 'roundabout',
                        'exit': 2,
                        'location': [77.6050, 12.9780],
                      },
                    },
                    {
                      'name': '',
                      'distance': 0.0,
                      'duration': 0.0,
                      'maneuver': {
                        'type': 'arrive',
                        'location': [77.6100, 12.9800],
                      },
                    },
                  ],
                },
              ],
            },
          ],
        },
        mode: TravelMode.walking,
      );

      expect(route, isNotNull);
      expect(route!.mode, TravelMode.walking);
      expect(route.points, hasLength(3));
      expect(route.distanceMeters, closeTo(1850.5, 0.1));
      expect(route.steps, hasLength(4));
      expect(route.steps[0].instruction, 'Head toward MG Road');
      expect(route.steps[1].instruction, 'Turn right onto Brigade Road');
      expect(route.steps[2].instruction, 'At the roundabout, take exit 2');
      expect(route.steps[3].instruction, 'Arrive at your destination');
    });
  });

  group('LiveLocationScreen Multi-Sharer State Selection', () {
    test('prefers active live message over older ended message regardless of doc order', () {
      const now = 2000000000000;
      final selected = LiveLocationScreen.selectLatestSharersFromPayloads(
        [
          {
            'messageId': 'active_msg',
            'senderId': 'partner_1',
            'timeSent': now - 60000,
            'fileMessageData': jsonEncode({
              'latitude': 12.9750,
              'longitude': 77.6050,
              'isLive': true,
              'liveUntil': now + 600000,
              'updatedAt': now - 5000,
              'heading': 90.0,
              'speed': 4.2,
              'accuracy': 8.0,
            }),
          },
          // Simulate an older ended live_location doc returned later by Firestore.
          {
            'messageId': 'old_ended_msg',
            'senderId': 'partner_1',
            'timeSent': now - 9000000,
            'fileMessageData': jsonEncode({
              'latitude': 12.9100,
              'longitude': 77.5100,
              'isLive': false,
              'liveUntil': now - 8000000,
              'updatedAt': now - 8000000,
            }),
          },
          {
            'messageId': 'my_live_msg',
            'senderId': 'me_1',
            'timeSent': now - 10000,
            'fileMessageData': jsonEncode({
              'latitude': 12.9800,
              'longitude': 77.6100,
              'isLive': true,
              'liveUntil': now + 300000,
              'updatedAt': now - 1000,
            }),
          },
        ],
        currentUserId: 'me_1',
        nowMs: now,
      );

      expect(selected.keys, containsAll(['partner_1', 'me_1']));
      expect(selected['partner_1']!.isLive, isTrue);
      expect(selected['partner_1']!.position.latitude, closeTo(12.9750, 0.0001));
      expect(selected['partner_1']!.speed, closeTo(4.2, 0.01));
      expect(selected['partner_1']!.heading, closeTo(90.0, 0.01));
      expect(selected['me_1']!.isMe, isTrue);
    });
  });

  group('Map Widgets Rendering & Controls', () {
    testWidgets('LocationMessageWidget displays place name, address, and updates live position',
        (tester) async {
      final futureUntil =
          DateTime.now().add(const Duration(minutes: 45)).millisecondsSinceEpoch;
      final firstJson = jsonEncode({
        'latitude': 12.9716,
        'longitude': 77.5946,
        'isLive': true,
        'liveUntil': futureUntil,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'speed': 3.5,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationMessageWidget(
              messageType: 'live_location',
              locationData: firstJson,
              isMe: false,
              messageId: 'msg_live_1',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Live Location'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.textContaining('km/h'), findsOneWidget);

      final updatedJson = jsonEncode({
        'latitude': 12.9788,
        'longitude': 77.6012,
        'isLive': true,
        'liveUntil': futureUntil,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'speed': 5.0,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationMessageWidget(
              messageType: 'live_location',
              locationData: updatedJson,
              isMe: false,
              messageId: 'msg_live_1',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'LiveLocationScreen renders Google-Maps UI on 360px phone, switches map types, and supports search/pin UI',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: LiveLocationScreen(
            initialLatitude: 12.9716,
            initialLongitude: 77.5946,
            sharerName: 'Queen Pooja',
            isLive: false,
            initialPlaceName: 'Sanctuary Point',
            initialAddress: 'MG Road, Bengaluru',
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('Sanctuary Point'), findsWidgets);
      expect(find.text('MG Road, Bengaluru'), findsOneWidget);
      expect(find.text('Google Maps'), findsOneWidget);

      // Open Map type sheet and switch to Hybrid (Satellite + Labels).
      await tester.tap(find.byIcon(Icons.layers_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Map type'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Night'), findsOneWidget);
      expect(find.text('Satellite'), findsOneWidget);
      expect(find.text('Hybrid'), findsOneWidget);
      expect(find.text('Terrain'), findsOneWidget);

      await tester.tap(find.text('Hybrid'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(MapStyleRegistry.styleNotifier.value, AppMapStyle.hybrid);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'LocationPickerSheet handles GPS unavailable cleanly and supports searching coordinates to drop a pin',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const channels = [
        MethodChannel('flutter.baseflow.com/geolocator'),
        MethodChannel('flutter.baseflow.com/geolocator_android'),
        MethodChannel('flutter.baseflow.com/geolocator_apple'),
      ];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final ch in channels) {
        messenger.setMockMethodCallHandler(ch, (call) async {
          if (call.method == 'isLocationServiceEnabled') return false;
          if (call.method == 'getLastKnownPosition') return null;
          if (call.method == 'checkPermission') return 0; // denied
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(ch, null));
      }

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: LocationPickerSheet(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Retry GPS'), findsOneWidget);
      expect(find.text('Location Settings'), findsOneWidget);

      // Search exact coordinates offline to pick a pin even when GPS is off.
      await tester.enterText(find.byType(TextField), '12.9716, 77.5946');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.text('Pinned Coordinates'), findsOneWidget);

      await tester.tap(find.text('Pinned Coordinates'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('Send Selected Location'), findsOneWidget);
    });
  });
}
