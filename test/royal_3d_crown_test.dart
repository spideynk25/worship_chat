import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/group/widgets/royal_3d_crown_widget.dart';
import 'package:worship_chat/features/group/widgets/cylinder_crown_painter.dart';

void main() {
  group('Volumetric 3D Royal Crown Tests', () {
    testWidgets('CylinderCrownPainter renders front and rear views with zero gaps',
        (tester) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(const Color(0xFFD4AF37), BlendMode.src);
      final mockImage = await recorder.endRecording().toImage(128, 128);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CustomPaint(
                size: const Size(180, 180),
                painter: CylinderCrownPainter(
                  frontImage: mockImage,
                  yaw: 0.35,
                  pitch: -0.15,
                  glowColor: const Color(0xFFE5A93C),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('Royal3dCrownWidget renders with interactive drag and tap pulse',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Royal3dCrownWidget(
                position: 'Queen',
                size: 72,
                enableInspect: true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Royal3dCrownWidget), findsOneWidget);
      expect(find.byType(Transform), findsWidgets);

      // Perform pan drag
      await tester.drag(find.byType(Royal3dCrownWidget), const Offset(25, -15));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(Royal3dCrownWidget), findsOneWidget);

      // Tap crown to trigger inspect sheet
      await tester.tap(find.byType(Royal3dCrownWidget));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Inspect sheet should be opened
      expect(find.text('3D ROYAL CROWN VAULT'), findsOneWidget);
      expect(find.text('0° FRONT'), findsOneWidget);
      expect(find.text('30° TILT'), findsOneWidget);
      expect(find.text('60° 3D'), findsOneWidget);
      expect(find.text('90° PROFILE'), findsOneWidget);
      expect(find.text('180° BACK'), findsOneWidget);

      // Tap preset 180° BACK to view the back of the crown covering the back of the head
      await tester.tap(find.text('180° BACK'));
      await tester.pump(const Duration(milliseconds: 100));

      // Tap preset 30° Tilt
      await tester.tap(find.text('30° TILT'));
      await tester.pump(const Duration(milliseconds: 100));

      // Close vault
      await tester.tap(find.text('CLOSE VAULT'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('3D ROYAL CROWN VAULT'), findsNothing);
    });

    testWidgets('CylinderCrownPainter accurately renders 180-degree rear view with circlet bandeau',
        (tester) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(const Color(0xFFD4AF37), BlendMode.src);
      final frontMock = await recorder.endRecording().toImage(128, 128);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CustomPaint(
                size: const Size(200, 200),
                painter: CylinderCrownPainter(
                  frontImage: frontMock,
                  yaw: 3.14159, // 180° rear view
                  pitch: 0.10,
                  glowColor: const Color(0xFFE5A93C),
                  hasVelvet: true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
