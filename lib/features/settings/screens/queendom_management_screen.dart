import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/features/group/utils/queendom_emblem_helper.dart';
import 'package:worship_chat/features/settings/models/queendom_customization_model.dart';
import 'package:worship_chat/features/settings/providers/queendom_customization_provider.dart';
import 'package:worship_chat/features/settings/widgets/queendom_color_picker.dart';

class QueendomManagementScreen extends ConsumerStatefulWidget {
  static const routeName = '/queendom-management-screen';

  const QueendomManagementScreen({super.key});

  @override
  ConsumerState<QueendomManagementScreen> createState() =>
      _QueendomManagementScreenState();
}

class _QueendomManagementScreenState
    extends ConsumerState<QueendomManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(queendomCustomizationProvider);
    final notifier = ref.read(queendomCustomizationProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161426),
        elevation: 0,
        title: const Text(
          'Queendom Customization',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            color: const Color(0xFF161426),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'reset') {
                _confirmResetDefaults(context, notifier);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt_rounded, color: Colors.orangeAccent, size: 19),
                    SizedBox(width: 10),
                    Text(
                      'Reset to Defaults',
                      style: TextStyle(color: Colors.white, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: tabColor,
          indicatorWeight: 3,
          labelColor: tabColor,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          tabs: [
            Tab(
              icon: const Icon(Icons.auto_awesome, size: 18),
              text: 'Categories (${state.allCategories.length})',
            ),
            Tab(
              icon: const Icon(Icons.shield_rounded, size: 18),
              text: 'Families (${state.familyOrder.length})',
            ),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF161426),
              Color(0xFF0F0E17),
            ],
          ),
        ),
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildCategoriesTab(state, notifier),
            _buildFamiliesTab(state, notifier),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CATEGORIES TAB
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCategoriesTab(
    QueendomCustomizationState state,
    QueendomCustomizationNotifier notifier,
  ) {
    final customCategories = state.categories.where((c) => c.isCustom).toList();
    final standardCategories = state.categories.where((c) => !c.isCustom).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        // Description Card
        _buildInfoCard(
          icon: Icons.info_outline_rounded,
          title: 'Queendom Group Categories',
          description:
              'Add, edit, or customize categories and positions. Use the color picker to craft accent colors, choose emblems, and configure family structure.',
        ),
        const SizedBox(height: 14),

        // Action Button: Add Category
        ElevatedButton.icon(
          onPressed: () => _showAddCategorySheet(context, notifier),
          icon: const Icon(Icons.add_circle_outline_rounded, size: 19),
          label: const Text(
            'Add New Category / Position',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: tabColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 3,
          ),
        ),
        const SizedBox(height: 22),

        // Custom Categories Section
        if (customCategories.isNotEmpty) ...[
          _buildSectionHeader(
            'CUSTOM CATEGORIES (${customCategories.length})',
            color: tabColor,
          ),
          const SizedBox(height: 8),
          ...customCategories.map((cat) => _buildCategoryTile(
                category: cat,
                isCustom: true,
                onEdit: () => _showEditCategorySheet(context, notifier, cat),
                onDelete: () => _confirmDeleteCategory(context, notifier, cat),
              )),
          const SizedBox(height: 18),
        ],

        // Default / Standard Categories Section
        _buildSectionHeader(
          'QUEENDOM CATEGORIES (${standardCategories.length})',
        ),
        const SizedBox(height: 8),
        ...standardCategories.map((cat) => _buildCategoryTile(
              category: cat,
              isCustom: false,
              onEdit: () => _showEditCategorySheet(context, notifier, cat),
              onDelete: () => _confirmDeleteCategory(context, notifier, cat),
            )),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCategoryTile({
    required QueendomCategory category,
    required bool isCustom,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161426),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCustom
              ? category.color.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
          width: isCustom ? 1.2 : 0.8,
        ),
      ),
      child: Row(
        children: [
          // Emoji / Emblem Container
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: category.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: category.color.withValues(alpha: 0.4),
                width: 1.0,
              ),
            ),
            child: Center(
              child: QueendomEmblemWidget(
                position: category.position,
                emoji: category.emoji,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Titles & Structure
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        category.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isCustom
                            ? tabColor.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isCustom ? 'Custom' : 'Default',
                        style: TextStyle(
                          color: isCustom ? tabColor : Colors.white54,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Position: ${category.position}',
                        style: TextStyle(color: Colors.grey[400], fontSize: 11.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('•', style: TextStyle(color: Colors.grey[600], fontSize: 10)),
                    const SizedBox(width: 6),
                    Text(
                      category.hasOtherFamilies ? 'Multiple Families' : 'Priority 1, 2..',
                      style: TextStyle(
                        color: category.hasOtherFamilies
                            ? const Color(0xFF64B5F6)
                            : const Color(0xFFFFB74D),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Color Indicator
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: category.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: category.color.withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // Edit Action
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Color(0xFF00E5FF), size: 19),
            tooltip: 'Edit Category',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onEdit,
          ),

          // Delete Action
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: Color(0xFFFF5252), size: 19),
            tooltip: 'Delete Category',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FAMILIES TAB
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFamiliesTab(
    QueendomCustomizationState state,
    QueendomCustomizationNotifier notifier,
  ) {
    final customFamilies =
        state.families.where((f) => !QueendomCategory.defaultFamilies.contains(f)).toList();
    final standardFamilies =
        state.families.where((f) => QueendomCategory.defaultFamilies.contains(f)).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        // Description Card
        _buildInfoCard(
          icon: Icons.shield_outlined,
          title: 'Queendom Royal Families',
          description:
              'Add, edit, or remove royal families. Families appear in group creation/editing dropdowns and are grouped under family crests.',
        ),
        const SizedBox(height: 14),

        // Action Button: Add Family
        ElevatedButton.icon(
          onPressed: () => _showAddFamilyDialog(context, notifier),
          icon: const Icon(Icons.add_circle_outline_rounded, size: 19),
          label: const Text(
            'Add New Royal Family',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: const Color(0xFF0F0E17),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 3,
          ),
        ),
        const SizedBox(height: 22),

        // Custom Families Section
        if (customFamilies.isNotEmpty) ...[
          _buildSectionHeader(
            'CUSTOM FAMILIES (${customFamilies.length})',
            color: const Color(0xFF00E5FF),
          ),
          const SizedBox(height: 8),
          ...customFamilies.map((fam) => _buildFamilyTile(
                family: fam,
                isCustom: true,
                onEdit: () => _showEditFamilyDialog(context, notifier, fam),
                onDelete: () => _confirmDeleteFamily(context, notifier, fam),
              )),
          const SizedBox(height: 18),
        ],

        // Default Families Section
        _buildSectionHeader(
          'QUEENDOM FAMILIES (${standardFamilies.length})',
        ),
        const SizedBox(height: 8),
        ...standardFamilies.map((fam) => _buildFamilyTile(
              family: fam,
              isCustom: false,
              onEdit: () => _showEditFamilyDialog(context, notifier, fam),
              onDelete: () => _confirmDeleteFamily(context, notifier, fam),
            )),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildFamilyTile({
    required String family,
    required bool isCustom,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161426),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCustom
              ? const Color(0xFF00E5FF).withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.08),
          width: isCustom ? 1.2 : 0.8,
        ),
      ),
      child: Row(
        children: [
          // Crest Container
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                width: 1.0,
              ),
            ),
            child: Center(
              child: QueendomFamilyEmblemWidget(
                family: family,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Family Title & Badge
          Expanded(
            child: Row(
              children: [
                Text(
                  family,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isCustom
                        ? const Color(0xFF00E5FF).withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isCustom ? 'Custom' : 'Default',
                    style: TextStyle(
                      color: isCustom ? const Color(0xFF00E5FF) : Colors.white54,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Edit Action
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Color(0xFF00E5FF), size: 19),
            tooltip: 'Edit Family',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onEdit,
          ),

          // Delete Action
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: Color(0xFFFF5252), size: 19),
            tooltip: 'Delete Family',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CATEGORY MODAL SHEETS (ADD & EDIT)
  // ─────────────────────────────────────────────────────────────────────────

  void _showAddCategorySheet(
    BuildContext context,
    QueendomCustomizationNotifier notifier,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161426),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _CategoryFormBottomSheet(
        onSave: (newCat) async {
          final messenger = ScaffoldMessenger.of(context);
          final res = await notifier.addCategory(newCat);
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          messenger.showSnackBar(
            SnackBar(
              content: Text(res.message),
              backgroundColor: res.success ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
            ),
          );
        },
      ),
    );
  }

  void _showEditCategorySheet(
    BuildContext context,
    QueendomCustomizationNotifier notifier,
    QueendomCategory category,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161426),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _CategoryFormBottomSheet(
        existingCategory: category,
        onSave: (updatedCat) async {
          final messenger = ScaffoldMessenger.of(context);
          final res = await notifier.editCategory(
            originalPosition: category.position,
            updatedCategory: updatedCat,
          );
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          messenger.showSnackBar(
            SnackBar(
              content: Text(res.message),
              backgroundColor: res.success ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FAMILY DIALOGS (ADD & EDIT)
  // ─────────────────────────────────────────────────────────────────────────

  void _showAddFamilyDialog(
    BuildContext context,
    QueendomCustomizationNotifier notifier,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161426),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.shield_rounded, color: Color(0xFFFFD700), size: 22),
              SizedBox(width: 8),
              Text(
                'Add Royal Family',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter family name (e.g. Celestial, Shadow, Seraphic):',
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Family name',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.shield_outlined, color: Color(0xFFFFD700)),
                  filled: true,
                  fillColor: const Color(0xFF0F0E17),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                final messenger = ScaffoldMessenger.of(context);
                final res = await notifier.addFamily(name);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(res.message),
                    backgroundColor:
                        res.success ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: const Color(0xFF0F0E17),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Save Family', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showEditFamilyDialog(
    BuildContext context,
    QueendomCustomizationNotifier notifier,
    String originalFamily,
  ) {
    final controller = TextEditingController(text: originalFamily);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161426),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.edit_outlined, color: Color(0xFF00E5FF), size: 22),
              SizedBox(width: 8),
              Text(
                'Edit Royal Family',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Update family name:',
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Family name',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.shield_outlined, color: Color(0xFFFFD700)),
                  filled: true,
                  fillColor: const Color(0xFF0F0E17),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.isEmpty) return;
                final messenger = ScaffoldMessenger.of(context);
                final res = await notifier.editFamily(
                  originalName: originalFamily,
                  updatedName: newName,
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(res.message),
                    backgroundColor:
                        res.success ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: const Color(0xFF0F0E17),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONFIRMATION DIALOGS
  // ─────────────────────────────────────────────────────────────────────────

  void _confirmDeleteCategory(
    BuildContext context,
    QueendomCustomizationNotifier notifier,
    QueendomCategory category,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161426),
        title: Text('Delete Category "${category.title}"?'),
        content: Text(
          category.isCustom
              ? 'This custom category will be removed from group creation and editing options.'
              : 'This Queendom category will be removed. You can restore it anytime with "Reset to Defaults".',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final res = await notifier.deleteCategory(category.position);
              messenger.showSnackBar(
                SnackBar(content: Text(res.message)),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteFamily(
    BuildContext context,
    QueendomCustomizationNotifier notifier,
    String family,
  ) {
    final isCustom = !QueendomCategory.defaultFamilies.contains(family);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161426),
        title: Text('Delete Family "$family"?'),
        content: Text(
          isCustom
              ? 'This custom family will be removed from group creation and editing options.'
              : 'This Queendom family will be removed. You can restore it anytime with "Reset to Defaults".',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final res = await notifier.deleteFamily(family);
              messenger.showSnackBar(
                SnackBar(content: Text(res.message)),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmResetDefaults(
    BuildContext context,
    QueendomCustomizationNotifier notifier,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161426),
        title: const Row(
          children: [
            Icon(Icons.restart_alt_rounded, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text('Reset to Defaults?'),
          ],
        ),
        content: const Text(
          'This will restore all 13 Queendom Categories and 13 Royal Families to their original settings. Any custom additions or edits will be reset.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final res = await notifier.resetAllToDefault();
              messenger.showSnackBar(SnackBar(content: Text(res.message)));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Reset All', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          color: color ?? Colors.white54,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161426),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tabColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UNIFIED CATEGORY FORM BOTTOM SHEET (ADD & EDIT WITH QUEENDOM COLOR PICKER)
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryFormBottomSheet extends StatefulWidget {
  final QueendomCategory? existingCategory;
  final Future<void> Function(QueendomCategory) onSave;

  const _CategoryFormBottomSheet({
    this.existingCategory,
    required this.onSave,
  });

  @override
  State<_CategoryFormBottomSheet> createState() => _CategoryFormBottomSheetState();
}

class _CategoryFormBottomSheetState extends State<_CategoryFormBottomSheet> {
  late final TextEditingController _positionController;
  late final TextEditingController _titleController;

  late String _selectedEmoji;
  late Color _selectedColor;
  late bool _hasOtherFamilies;
  bool _isSaving = false;

  final List<String> _quickEmojis = [
    '✨', '🔮', '🗡️', '🌙', '🕊️', '🪐', '💎', '⚜️',
    '🧿', '💫', '🌹', '🌸', '⚡', '🪽', '👑', '🦁',
    '☀️', '🌟', '🏮', '🍂', '🪷', '🏵️', '🪻', '🍁',
  ];

  static const List<Color> _royalPresets = [
    Color(0xFFFFD700), // Imperial Gold
    Color(0xFFCFAB09), // Golden Blossom
    Color(0xFFFF6347), // Coral Queen
    Color(0xFFE74C3C), // Crimson Supreme
    Color(0xFFE91E63), // Rose Magenta
    Color(0xFFFF69B4), // Hot Pink
    Color(0xFFBA68C8), // Orchid Princess
    Color(0xFF8E44AD), // Royal Violet
    Color(0xFF9B59B6), // Goddess Purple
    Color(0xFF4A3570), // Dark Angel Indigo
    Color(0xFF4A90E2), // Sapphire Core
    Color(0xFF00E5FF), // Cyan Aura
    Color(0xFF1ABC9C), // Jade Enchantress
    Color(0xFF2ECC71), // Emerald Witch
  ];

  @override
  void initState() {
    super.initState();
    final cat = widget.existingCategory;
    _positionController = TextEditingController(text: cat?.position ?? '');
    _titleController = TextEditingController(text: cat?.title ?? '');
    _selectedEmoji = cat?.emoji ?? '✨';
    _selectedColor = cat?.color ?? const Color(0xFFFFD700);
    _hasOtherFamilies = cat?.hasOtherFamilies ?? false;
  }

  @override
  void dispose() {
    _positionController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existingCategory != null;

  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  Future<void> _openColorPicker() async {
    final picked = await QueendomColorPicker.showColorPickerDialog(
      context,
      currentColor: _selectedColor,
      title: _isEditing ? 'Edit Accent Color' : 'Pick Accent Color',
    );
    if (picked != null && mounted) {
      setState(() => _selectedColor = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  _isEditing ? Icons.edit_note_rounded : Icons.auto_awesome,
                  color: tabColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  _isEditing ? 'Edit Category' : 'Add New Queendom Category',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Colors.white12),
            const SizedBox(height: 10),

            // Live Preview Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0E17),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _selectedColor.withValues(alpha: 0.5), width: 1.2),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _selectedColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _selectedColor, width: 0.8),
                    ),
                    child: Center(
                      child: Text(_selectedEmoji, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _titleController.text.trim().isNotEmpty
                              ? _titleController.text.trim()
                              : (_positionController.text.trim().isNotEmpty
                                  ? _positionController.text.trim()
                                  : 'Category Title Preview'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          _positionController.text.trim().isNotEmpty
                              ? 'Position: ${_positionController.text.trim()}'
                              : 'Position: (e.g. Archangel)',
                          style: TextStyle(color: Colors.grey[400], fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: _hasOtherFamilies
                          ? const Color(0xFF64B5F6).withValues(alpha: 0.2)
                          : const Color(0xFFFFB74D).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _hasOtherFamilies ? 'Families' : 'Priority 1, 2..',
                      style: TextStyle(
                        color: _hasOtherFamilies
                            ? const Color(0xFF64B5F6)
                            : const Color(0xFFFFB74D),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 1. Position Input
            const Text(
              'Category Position Name (Singular role, e.g. "Archangel", "Valkyrie"):',
              style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _positionController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(
                hint: 'e.g. Archangel, Valkyrie, High Priestess',
                icon: Icons.badge_outlined,
              ),
            ),
            const SizedBox(height: 14),

            // 2. Display Title Input
            const Text(
              'Display Title (Plural / Tab title, e.g. "Archangels", "Valkyries"):',
              style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(
                hint: 'Defaults to position if left blank',
                icon: Icons.title_rounded,
              ),
            ),
            const SizedBox(height: 14),

            // 3. Emoji Selection
            const Text(
              'Emblem Emoji:',
              style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickEmojis.map((emoji) {
                final isSelected = _selectedEmoji == emoji;
                return GestureDetector(
                  onTap: () => setState(() => _selectedEmoji = emoji),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? tabColor.withValues(alpha: 0.25)
                          : const Color(0xFF0F0E17),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? tabColor : Colors.white12,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // 4. Accent Color Selection with Full Color Picker
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Accent Theme Color:',
                  style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
                TextButton.icon(
                  onPressed: _openColorPicker,
                  icon: const Icon(Icons.colorize_rounded, size: 15, color: tabColor),
                  label: const Text(
                    'Color Picker',
                    style: TextStyle(color: tabColor, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Interactive Color Preview Bar (tap to open color picker)
            InkWell(
              onTap: _openColorPicker,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0E17),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _selectedColor.withValues(alpha: 0.4), width: 1.2),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _selectedColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _selectedColor.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _colorToHex(_selectedColor),
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const Text(
                          'Tap to pick any custom color (HSV / Hex)',
                          style: TextStyle(color: Colors.white38, fontSize: 10.5),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.tune_rounded, color: Colors.white54, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Quick Royal Presets Swatches
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _royalPresets.map((color) {
                final isSelected = _selectedColor.toARGB32() == color.toARGB32();
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.white12,
                        width: isSelected ? 2.5 : 1.0,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.6),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // 5. Structure Mode Toggle
            Material(
              color: const Color(0xFF0F0E17),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.white12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Has Multiple Royal Families',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    _hasOtherFamilies
                        ? 'Groups can choose a family (Aura, Core, Divine, etc.)'
                        : 'Groups use sequential numerical Priority (1, 2, 3...)',
                    style: TextStyle(
                      color: _hasOtherFamilies
                          ? const Color(0xFF64B5F6)
                          : const Color(0xFFFFB74D),
                      fontSize: 11,
                    ),
                  ),
                  value: _hasOtherFamilies,
                  activeThumbColor: tabColor,
                  onChanged: (val) => setState(() => _hasOtherFamilies = val),
                ),
              ),
            ),
            const SizedBox(height: 22),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _handleSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: tabColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _isEditing ? 'Save Changes' : 'Save Category',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12.5),
      prefixIcon: Icon(icon, color: tabColor, size: 20),
      filled: true,
      fillColor: const Color(0xFF0F0E17),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: tabColor),
      ),
    );
  }

  void _handleSave() async {
    final pos = _positionController.text.trim();
    if (pos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter category position name')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : pos;

    final updatedCategory = QueendomCategory(
      title: title,
      position: pos,
      color: _selectedColor,
      emoji: _selectedEmoji,
      hasOtherFamilies: _hasOtherFamilies,
      isCustom: widget.existingCategory?.isCustom ?? true,
    );

    await widget.onSave(updatedCategory);
  }
}
