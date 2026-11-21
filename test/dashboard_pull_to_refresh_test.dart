import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/features/dashboard/repositories/event_repository.dart';
import 'package:worship_chat/features/dashboard/screens/dashboard_page.dart';
import 'package:worship_chat/models/event.dart';

class _FakeEventRepository implements EventRepository {
  int loadEventsCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #fetchEvents) {
      loadEventsCount++;
      return Future.value(<Event>[]);
    }
    if (invocation.memberName == #eventsStream) {
      return Stream.value(<Event>[]);
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  testWidgets('DashboardPage contains RefreshIndicator with proper styling and triggers on refresh',
      (tester) async {
    final fakeRepo = _FakeEventRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: DashboardPage(),
          ),
        ),
      ),
    );

    // Initial pump
    await tester.pump();

    // Verify RefreshIndicator exists
    final refreshIndicatorFinder = find.byType(RefreshIndicator);
    expect(refreshIndicatorFinder, findsOneWidget);

    final refreshIndicator = tester.widget<RefreshIndicator>(refreshIndicatorFinder);
    expect(refreshIndicator.color, tabColor);
    expect(refreshIndicator.backgroundColor, const Color(0xFF1B1528));

    // Verify SingleChildScrollView uses AlwaysScrollableScrollPhysics
    final scrollViewFinder = find.byType(SingleChildScrollView).first;
    final scrollView = tester.widget<SingleChildScrollView>(scrollViewFinder);
    expect(scrollView.physics, isA<AlwaysScrollableScrollPhysics>());

    // Trigger pull-to-refresh gesture (drag down)
    await tester.fling(scrollViewFinder, const Offset(0.0, 300.0), 1000.0);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // Verify event refresh was invoked
    expect(fakeRepo.loadEventsCount, greaterThan(0));
  });
}
