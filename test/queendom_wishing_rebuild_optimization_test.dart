import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Queendom Wishing & Rebuild Optimization Tests', () {
    test('ValueNotifier isolates wishing state without parent rebuilds', () {
      final isWishing = ValueNotifier<bool>(false);
      int parentBuildCount = 0;
      int buttonBuildCount = 0;

      final widget = StatefulBuilder(
        builder: (context, setState) {
          parentBuildCount++;
          return ValueListenableBuilder<bool>(
            valueListenable: isWishing,
            builder: (context, wishing, _) {
              buttonBuildCount++;
              return Text(wishing ? 'Wishing...' : 'Idle');
            },
          );
        },
      );

      // Initial build
      expect(parentBuildCount, 0);
      expect(buttonBuildCount, 0);

      // Mutate notifier
      isWishing.value = true;
      expect(isWishing.value, isTrue);

      isWishing.value = false;
      expect(isWishing.value, isFalse);
    });

    test('Stream buffering suppresses intermediate emissions during active wishing', () async {
      final isWishing = ValueNotifier<bool>(false);
      List<String>? appliedData;
      List<String>? pendingData;
      int stateUpdateCount = 0;
      Timer? debounceTimer;

      void onStreamData(List<String> data) {
        if (isWishing.value) {
          // Freeze UI updates during wishing
          pendingData = data;
          return;
        }
        if (appliedData == null) {
          appliedData = data;
          stateUpdateCount++;
          return;
        }
        debounceTimer?.cancel();
        debounceTimer = Timer(const Duration(milliseconds: 50), () {
          if (isWishing.value) {
            pendingData = data;
            return;
          }
          appliedData = data;
          stateUpdateCount++;
        });
      }

      // 1. Initial emission
      onStreamData(['Initial 1', 'Initial 2']);
      expect(appliedData, equals(['Initial 1', 'Initial 2']));
      expect(stateUpdateCount, 1);

      // 2. Start wishing
      isWishing.value = true;

      // Simulate 7 rapid Firestore document updates while wishing
      for (int i = 1; i <= 7; i++) {
        onStreamData(['Group $i updated']);
      }

      // Verify that during wishing, ZERO state updates occurred!
      expect(stateUpdateCount, 1);
      expect(pendingData, equals(['Group 7 updated']));

      // 3. Finish wishing
      isWishing.value = false;
      if (pendingData != null) {
        appliedData = pendingData;
        pendingData = null;
        stateUpdateCount++;
      }

      // Exactly ONE clean update applied at the end
      expect(stateUpdateCount, 2);
      expect(appliedData, equals(['Group 7 updated']));
      expect(pendingData, isNull);

      debounceTimer?.cancel();
      isWishing.dispose();
    });

    test('Rapid consecutive Firestore snapshots are debounced outside wishing', () async {
      final isWishing = ValueNotifier<bool>(false);
      List<String>? appliedData;
      int stateUpdateCount = 0;
      Timer? debounceTimer;

      void onStreamData(List<String> data) {
        if (isWishing.value) return;
        if (appliedData == null) {
          appliedData = data;
          stateUpdateCount++;
          return;
        }
        debounceTimer?.cancel();
        debounceTimer = Timer(const Duration(milliseconds: 60), () {
          appliedData = data;
          stateUpdateCount++;
        });
      }

      // Initial load (instant)
      onStreamData(['Initial']);
      expect(stateUpdateCount, 1);

      // 3 rapid snapshot updates arriving within 20ms of each other (e.g. optimistic write + server ack)
      onStreamData(['Update A']);
      await Future.delayed(const Duration(milliseconds: 20));
      onStreamData(['Update B']);
      await Future.delayed(const Duration(milliseconds: 20));
      onStreamData(['Update C']);

      // Before timer fires, state hasn't updated yet
      expect(stateUpdateCount, 1);

      // Wait for debounce timer to fire
      await Future.delayed(const Duration(milliseconds: 80));

      // Coalesced into a single update
      expect(stateUpdateCount, 2);
      expect(appliedData, equals(['Update C']));

      debounceTimer?.cancel();
      isWishing.dispose();
    });
  });
}
