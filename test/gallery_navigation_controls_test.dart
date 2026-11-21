import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/features/group/widgets/gallery_navigation_controls.dart';

void main() {
  tearDown(() => AppCapabilities.debugOverride = null);

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('$platform gallery can move between photos with a pointer', (
      tester,
    ) async {
      AppCapabilities.debugOverride = AppCapabilities(
        platform: platform,
        isTablet: false,
      );
      await tester.pumpWidget(const MaterialApp(home: _PhotoPager()));

      final previous = find.widgetWithIcon(IconButton, Icons.chevron_left);
      final next = find.widgetWithIcon(IconButton, Icons.chevron_right);
      expect(tester.widget<IconButton>(previous).onPressed, isNull);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('Photo 2'), findsOneWidget);
      expect(tester.widget<IconButton>(next).onPressed, isNull);

      await tester.tap(previous);
      await tester.pumpAndSettle();
      expect(find.text('Photo 1'), findsOneWidget);
      expect(tester.widget<IconButton>(previous).onPressed, isNull);
    });
  }

  testWidgets('tablets retain swipe navigation without desktop controls', (
    tester,
  ) async {
    AppCapabilities.debugOverride = const AppCapabilities(
      platform: TargetPlatform.iOS,
      isTablet: true,
    );
    await tester.pumpWidget(const MaterialApp(home: _PhotoPager()));
    expect(find.byType(IconButton), findsNothing);
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Photo 2'), findsOneWidget);
  });
}

class _PhotoPager extends StatefulWidget {
  const _PhotoPager();

  @override
  State<_PhotoPager> createState() => _PhotoPagerState();
}

class _PhotoPagerState extends State<_PhotoPager> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _controller,
            onPageChanged: (index) => setState(() => _index = index),
            children: const [
              Center(child: Text('Photo 1')),
              Center(child: Text('Photo 2')),
            ],
          ),
          GalleryNavigationControls(
            controller: _controller,
            currentIndex: _index,
            imageCount: 2,
          ),
        ],
      ),
    );
  }
}
