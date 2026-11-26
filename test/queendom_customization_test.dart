import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/features/group/utils/group_template_helper.dart';
import 'package:worship_chat/features/settings/models/queendom_customization_model.dart';
import 'package:worship_chat/features/settings/providers/queendom_customization_provider.dart';
import 'package:worship_chat/features/settings/screens/queendom_management_screen.dart';
import 'package:worship_chat/features/settings/screens/settings_screen.dart';
import 'package:worship_chat/features/settings/widgets/queendom_color_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('QueendomCustomization Model & Provider Tests', () {
    test('Default families and categories are pre-populated', () {
      final notifier = QueendomCustomizationNotifier();
      final state = notifier.state;

      expect(state.customFamilies.isEmpty, isTrue);
      expect(state.customCategories.isEmpty, isTrue);

      // Default 13 families + 'None'
      expect(state.allFamilies.contains('None'), isTrue);
      expect(state.allFamilies.contains('Aura'), isTrue);
      expect(state.allFamilies.contains('Core'), isTrue);
      expect(state.allFamilies.contains('Velisse'), isTrue);
      expect(state.familyOrder.length, 13);

      // Default 13 categories + 'None'
      expect(state.allPositions.contains('None'), isTrue);
      expect(state.allPositions.contains('Aura Elixiria'), isTrue);
      expect(state.allPositions.contains('Goddess'), isTrue);
      expect(state.allCategories.length, 13);
    });

    test('Adding, editing, deleting, and resetting families works and persists', () async {
      final notifier = QueendomCustomizationNotifier();

      // 1. Add custom family
      final addRes = await notifier.addFamily('Celestial');
      expect(addRes.success, isTrue);
      expect(notifier.state.customFamilies.contains('Celestial'), isTrue);
      expect(notifier.state.allFamilies.contains('Celestial'), isTrue);

      // Duplicate add fails
      final dupRes = await notifier.addFamily('celestial');
      expect(dupRes.success, isFalse);

      // 2. Edit family
      final editRes = await notifier.editFamily(
        originalName: 'Celestial',
        updatedName: 'Celestial Seraph',
      );
      expect(editRes.success, isTrue);
      expect(notifier.state.allFamilies.contains('Celestial Seraph'), isTrue);
      expect(notifier.state.allFamilies.contains('Celestial'), isFalse);

      // Edit non-existent family fails
      final editGhost = await notifier.editFamily(
        originalName: 'Unknown',
        updatedName: 'Something',
      );
      expect(editGhost.success, isFalse);

      // 3. Delete family
      final delRes = await notifier.deleteFamily('Celestial Seraph');
      expect(delRes.success, isTrue);
      expect(notifier.state.allFamilies.contains('Celestial Seraph'), isFalse);

      // Deleting already removed family fails
      final delAgain = await notifier.deleteFamily('Celestial Seraph');
      expect(delAgain.success, isFalse);

      // 4. Reset to defaults
      await notifier.deleteFamily('Velisse');
      expect(notifier.state.allFamilies.contains('Velisse'), isFalse);
      final resetRes = await notifier.resetFamiliesToDefault();
      expect(resetRes.success, isTrue);
      expect(notifier.state.allFamilies.contains('Velisse'), isTrue);
      expect(notifier.state.familyOrder.length, 13);
    });

    test('Adding, editing, deleting, and resetting categories works and persists', () async {
      final notifier = QueendomCustomizationNotifier();

      const newCategory = QueendomCategory(
        title: 'Archangels',
        position: 'Archangel',
        color: Color(0xFF00E5FF),
        emoji: '🪽',
        hasOtherFamilies: true,
      );

      // 1. Add category
      final addRes = await notifier.addCategory(newCategory);
      expect(addRes.success, isTrue);
      expect(notifier.state.customCategories.any((c) => c.position == 'Archangel'), isTrue);
      expect(notifier.state.allPositions.contains('Archangel'), isTrue);

      // Duplicate add fails
      final dupRes = await notifier.addCategory(newCategory);
      expect(dupRes.success, isFalse);

      // Check structure
      expect(notifier.state.categoryHasOtherFamilies('Archangel'), isTrue);
      expect(GroupTemplateHelper.categoryHasOtherFamilies('Archangel'), isTrue);

      // 2. Edit category
      final editRes = await notifier.editCategory(
        originalPosition: 'Archangel',
        updatedCategory: const QueendomCategory(
          title: 'Seraphim Angels',
          position: 'Seraph',
          color: Color(0xFFFF1493),
          emoji: '🕊️',
          hasOtherFamilies: false,
        ),
      );
      expect(editRes.success, isTrue);
      expect(notifier.state.allPositions.contains('Seraph'), isTrue);
      expect(notifier.state.allPositions.contains('Archangel'), isFalse);
      final seraphCat = notifier.state.getCategoryByPosition('Seraph');
      expect(seraphCat, isNotNull);
      expect(seraphCat!.title, 'Seraphim Angels');
      expect(seraphCat.color, const Color(0xFFFF1493));

      // 3. Delete category
      final delRes = await notifier.deleteCategory('Seraph');
      expect(delRes.success, isTrue);
      expect(notifier.state.allPositions.contains('Seraph'), isFalse);

      // 4. Reset categories to defaults
      await notifier.deleteCategory('Goddess');
      expect(notifier.state.allPositions.contains('Goddess'), isFalse);
      final resetRes = await notifier.resetCategoriesToDefault();
      expect(resetRes.success, isTrue);
      expect(notifier.state.allPositions.contains('Goddess'), isTrue);
      expect(notifier.state.allCategories.length, 13);
    });

    test('Template generator formats deity name and wishes for custom category', () async {
      final notifier = QueendomCustomizationNotifier();
      await notifier.addCategory(
        const QueendomCategory(
          title: 'Valkyries',
          position: 'Valkyrie',
          color: Color(0xFFFF69B4),
          emoji: '🗡️',
          hasOtherFamilies: true,
        ),
      );

      // Generate template with family
      final withFam = GroupTemplateHelper.generateTemplate(
        position: 'Valkyrie',
        name: 'Freya',
        family: 'Celestial',
      );
      expect(withFam.livingPlace.contains('SANCTUM OF'), isTrue);
      expect(withFam.livingPlace.contains('CELESTIAL VALKYRIE FREYA'), isTrue);
      expect(withFam.wish.contains('Hail Celestial Valkyrie Freya'), isTrue);

      // Clean up
      await notifier.deleteCategory('Valkyrie');
    });

    test('Migrates legacy short default titles to full names while preserving user edits', () async {
      SharedPreferences.setMockInitialValues({
        QueendomCustomizationNotifier.allCategoriesPrefKey: [
          '{"title":"Aura Goddesses","position":"Aura Elixiria","color":4294956800,"emoji":"","hasOtherFamilies":false,"isCustom":false}',
          '{"title":"Custom Supreme Title","position":"Core Supreme Goddess","color":4283076834,"emoji":"","hasOtherFamilies":false,"isCustom":false}',
          '{"title":"Golden Blossom","position":"Golden Blossom Goddess","color":4291799817,"emoji":"","hasOtherFamilies":false,"isCustom":false}',
        ],
      });

      final notifier = QueendomCustomizationNotifier();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.getCategoryByPosition('Aura Elixiria')?.title, 'Aura Elixiria Goddesses');
      expect(notifier.state.getCategoryByPosition('Core Supreme Goddess')?.title, 'Custom Supreme Title');
      expect(notifier.state.getCategoryByPosition('Golden Blossom Goddess')?.title, 'Golden Blossom Goddesses');
    });
  });

  group('QueendomColorPicker Tests', () {
    testWidgets('QueendomColorPicker initializes and updates from hex text input', (tester) async {
      Color pickedColor = const Color(0xFFFF0000);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueendomColorPicker(
              initialColor: const Color(0xFFFF0000),
              onColorChanged: (c) => pickedColor = c,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Hex code input has #FF0000
      expect(find.text('#FF0000'), findsOneWidget);

      // Enter a new hex code #00FF00 (Green)
      await tester.enterText(find.byType(TextField), '#00FF00');
      await tester.pumpAndSettle();

      expect(pickedColor.toARGB32(), const Color(0xFF00FF00).toARGB32());
    });

    testWidgets('Tapping Royal Preset swatch updates picked color', (tester) async {
      Color pickedColor = const Color(0xFF000000);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueendomColorPicker(
              initialColor: const Color(0xFF000000),
              onColorChanged: (c) => pickedColor = c,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on Imperial Gold preset (first royal preset)
      final goldPreset = find.byWidgetPredicate(
        (w) => w is Container && (w.decoration is BoxDecoration) &&
            ((w.decoration as BoxDecoration).color == const Color(0xFFFFD700)),
      );
      expect(goldPreset, findsWidgets);

      await tester.tap(goldPreset.first);
      await tester.pumpAndSettle();

      expect(pickedColor.toARGB32(), const Color(0xFFFFD700).toARGB32());
    });
  });

  group('SettingsScreen Navigation & Clean UI Tests', () {
    testWidgets('SettingsScreen has 0 edit nav options (Edit Profile removed and user tile is static)', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify 'Settings' app bar title
      expect(find.text('Settings'), findsOneWidget);

      // Verify 'Edit Profile' row is completely REMOVED
      expect(find.text('Edit Profile'), findsNothing);

      // Verify Queendom Customization row exists
      expect(find.text('Queendom Families & Categories'), findsOneWidget);
      expect(
        find.text('Add custom families, positions & group categories'),
        findsOneWidget,
      );

      // Verify Display Settings row exists
      expect(find.text('Display Settings'), findsOneWidget);
    });

    testWidgets('Tapping Queendom Families & Categories navigates to QueendomManagementScreen', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on Queendom Families & Categories
      await tester.tap(find.text('Queendom Families & Categories'));
      await tester.pumpAndSettle();

      // Verify navigation to QueendomManagementScreen
      expect(find.byType(QueendomManagementScreen), findsOneWidget);
      expect(find.text('Queendom Customization'), findsOneWidget);
      expect(find.textContaining('Categories ('), findsOneWidget);
      expect(find.textContaining('Families ('), findsOneWidget);
      expect(find.text('Add New Category / Position'), findsOneWidget);
    });
  });

  group('QueendomManagementScreen UI Tests', () {
    testWidgets('Renders categories and families tabs with Edit & Delete options and Color Picker', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: QueendomManagementScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Categories tab active by default
      expect(find.text('Add New Category / Position'), findsOneWidget);
      expect(find.text('Aura Elixiria Goddesses'), findsOneWidget);
      expect(find.text('Core Supreme Goddesses'), findsOneWidget);
      expect(find.text('Goddesses'), findsOneWidget);

      // Edit and Delete icons present for categories
      expect(find.byTooltip('Edit Category'), findsWidgets);
      expect(find.byTooltip('Delete Category'), findsWidgets);

      // Tap Edit Category on first item
      await tester.tap(find.byTooltip('Edit Category').first);
      await tester.pumpAndSettle();

      // Verify Edit Category bottom sheet opened
      expect(find.text('Edit Category'), findsOneWidget);
      expect(find.text('Color Picker'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);

      // Tap Color Picker button inside sheet
      await tester.tap(find.text('Color Picker'));
      await tester.pumpAndSettle();

      // Verify QueendomColorPicker dialog opens
      expect(find.byType(QueendomColorPicker), findsOneWidget);
      expect(find.text('Edit Accent Color'), findsOneWidget);
      expect(find.text('Apply Color'), findsOneWidget);

      // Close dialog and bottom sheet
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Switch to Families tab
      await tester.tap(find.textContaining('Families ('));
      await tester.pumpAndSettle();

      expect(find.text('Add New Royal Family'), findsOneWidget);
      expect(find.text('Aura'), findsOneWidget);
      expect(find.text('Core'), findsOneWidget);
      expect(find.text('Velisse'), findsOneWidget);

      // Edit and Delete icons present for families
      expect(find.byTooltip('Edit Family'), findsWidgets);
      expect(find.byTooltip('Delete Family'), findsWidgets);

      // Tap Edit Family on first family
      await tester.tap(find.byTooltip('Edit Family').first);
      await tester.pumpAndSettle();

      // Verify Edit Family dialog opens
      expect(find.text('Edit Royal Family'), findsOneWidget);
      expect(find.text('Update family name:'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
}
