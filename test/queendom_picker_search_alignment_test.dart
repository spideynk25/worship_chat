import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Connect Queendom search bar hint text and entered text are perfectly centered',
      (tester) async {
    final searchController = TextEditingController();
    String searchQuery = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF201B34),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: TextField(
                    controller: searchController,
                    textAlignVertical: TextAlignVertical.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    onChanged: (val) => setState(() => searchQuery = val.trim()),
                    decoration: InputDecoration(
                      hintText: 'Search Queendom group...',
                      hintStyle: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.white38,
                        size: 18,
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 42,
                      ),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                color: Colors.white54,
                                size: 16,
                              ),
                              splashRadius: 16,
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                searchController.clear();
                                setState(() => searchQuery = '');
                              },
                            )
                          : null,
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 42,
                      ),
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify search icon and hint text exist
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.text('Search Queendom group...'), findsOneWidget);

    final containerCenter = tester.getCenter(find.byType(TextField)).dy;
    final iconCenter = tester.getCenter(find.byIcon(Icons.search)).dy;
    final hintCenter = tester.getCenter(find.text('Search Queendom group...')).dy;

    // Both icon and hint text should align with the container vertical center (within 1px tolerance)
    expect((hintCenter - iconCenter).abs(), lessThanOrEqualTo(1.0));
    expect((hintCenter - containerCenter).abs(), lessThanOrEqualTo(1.0));

    // Type text and verify entered text alignment
    await tester.enterText(find.byType(TextField), 'Pooja');
    await tester.pumpAndSettle();

    final textCenter = tester.getCenter(find.text('Pooja')).dy;
    expect((textCenter - iconCenter).abs(), lessThanOrEqualTo(1.0));
    expect(find.byIcon(Icons.clear), findsOneWidget);

    // Tap clear button
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(find.text('Search Queendom group...'), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsNothing);
  });
}
