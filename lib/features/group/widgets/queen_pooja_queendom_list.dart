import 'dart:developer';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/common/widgets/loader.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/screens/group_chat_screen.dart';
import 'package:worship_chat/models/group.dart';

class QueenPoojaQueendomList extends ConsumerStatefulWidget {
  const QueenPoojaQueendomList({super.key});

  @override
  ConsumerState<QueenPoojaQueendomList> createState() =>
      _QueenPoojaQueendomListState();
}

class _QueenPoojaQueendomListState extends ConsumerState<QueenPoojaQueendomList>
    with AutomaticKeepAliveClientMixin {
  // ── Keep this widget alive so scroll position survives navigation ──────────
  @override
  bool get wantKeepAlive => true;

  int selectedCategoryIndex = 0;

  // One ScrollController per category tab so each list remembers its own
  // position independently.
  final Map<int, ScrollController> _scrollControllers = {};

  ScrollController _controllerFor(int index) {
    return _scrollControllers.putIfAbsent(index, () => ScrollController());
  }

  // Sidebar ScrollController so the sidebar position is also preserved.
  final ScrollController _sidebarScrollController = ScrollController();

  @override
  void dispose() {
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    _sidebarScrollController.dispose();
    super.dispose();
  }

  final categories = [
    _CategoryData('Aura Goddesses', 'Aura Elixiria', Color(0xFFFFD700), '☀️'),
    _CategoryData(
      'Core Supreme',
      'Core Supreme Goddess',
      Color(0xFF4A90E2),
      '🌟',
    ),
    _CategoryData('Supreme', 'Supreme Goddess', Color(0xFFE74C3C), '🏮'),
    _CategoryData(
      'Golden Blossom',
      'Golden Blossom Goddess',
      Color.fromARGB(255, 207, 171, 9),
      '🍂',
    ),
    _CategoryData('Goddesses', 'Goddess', Color(0xFF9B59B6), '🪷'),
    _CategoryData('Demi', 'Demi Goddess', Color(0xFFFF69B4), '🏵️'),
    _CategoryData('Dark Angels', 'Dark Angel', Color(0xFF4A3570), '🪻'),
    _CategoryData('Queens', 'Queen', Color(0xFFFF6347), '👑'),
    _CategoryData('Elfwitches', 'Elfwitch', Color(0xFF2ECC71), '🍁'),
    _CategoryData('Enchantresses', 'Enchantress', Color(0xFF1ABC9C), '🍀'),
    _CategoryData(
      'First Born Princess',
      'First Born Princess',
      Color(0xFF8E44AD),
      '🌺',
    ),
    _CategoryData(
      'Second Born Princess',
      'Second Born Princess',
      Color(0xFFBA68C8),
      '🌸',
    ),
    _CategoryData(
      'Third Born Princess',
      'Third Born Princess',
      Color(0xFFCE93D8),
      '🌼',
    ),
  ];

  final familyOrder = [
    'Aura',
    'Core',
    'Main',
    'Eternal',
    'Divine',
    'Wicked',
    'Lustra',
    'Rumia',
    'Erotica',
    'Elegant',
    'Elora',
    'Zyra',
  ];

  int _getFamilyOrderIndex(String? family) {
    if (family == null || family.isEmpty || family == 'None') {
      return familyOrder.length;
    }
    final index = familyOrder.indexOf(family);
    return index == -1 ? familyOrder.length : index;
  }

  int _getUnseenCountForCategory(List<GroupModel> groups, String position) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return 0;
    return groups
        .where(
          (g) => g.position == position && g.hasUnseenForUser(currentUserId),
        )
        .length;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin

    return StreamBuilder<List<GroupModel>>(
      stream: ref.watch(groupControllerProvider).getQueenPoojaStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Loader();
        }
        if (snapshot.hasError) {
          log("Error loading groups: ${snapshot.error}");
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                const SizedBox(height: 16),
                Text(
                  "Error loading groups",
                  style: TextStyle(fontSize: 18, color: Colors.red[400]),
                ),
                const SizedBox(height: 8),
                Text(
                  "${snapshot.error}",
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final groups = snapshot.data ?? [];
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        final selectedCategory = categories[selectedCategoryIndex];

        final filteredGroups = groups
            .where((g) => g.position == selectedCategory.position)
            .toList();

        filteredGroups.sort((a, b) {
          final aFamilyIndex = _getFamilyOrderIndex(a.family);
          final bFamilyIndex = _getFamilyOrderIndex(b.family);
          if (aFamilyIndex != bFamilyIndex) {
            return aFamilyIndex.compareTo(bFamilyIndex);
          }
          return a.name.compareTo(b.name);
        });

        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 70),
              child: Column(
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          selectedCategory.color,
                          selectedCategory.color.withOpacity(0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: selectedCategory.color.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Text(
                          selectedCategory.emoji,
                          style: const TextStyle(fontSize: 32),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            selectedCategory.title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Groups list — uses a per-category ScrollController
                  Expanded(
                    child: filteredGroups.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.inbox_outlined,
                                  size: 80,
                                  color: Colors.grey[700],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No groups yet',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            // Key forces Flutter to keep this list's state
                            // separate for each category tab.
                            key: PageStorageKey(
                              'pooja_list_$selectedCategoryIndex',
                            ),
                            controller: _controllerFor(selectedCategoryIndex),
                            padding: const EdgeInsets.all(12),
                            itemCount: filteredGroups.length,
                            itemBuilder: (context, index) {
                              final group = filteredGroups[index];
                              final hasUnseen =
                                  currentUserId != null &&
                                  group.hasUnseenForUser(currentUserId);
                              return QueendomGroupCard(
                                group: group,
                                accentColor: selectedCategory.color,
                                hasUnseen: hasUnseen,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),

            // Sidebar
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 70,
                decoration: BoxDecoration(
                  color: Colors.black,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(2, 0),
                    ),
                  ],
                ),
                child: ListView.builder(
                  controller: _sidebarScrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final isSelected = selectedCategoryIndex == index;
                    final unseenCount = _getUnseenCountForCategory(
                      groups,
                      category.position,
                    );

                    return GestureDetector(
                      onTap: () =>
                          setState(() => selectedCategoryIndex = index),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Stack(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              width: double.infinity,
                              height: 54,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? category.color
                                    : Colors.grey[900],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? category.color
                                      : Colors.grey[800]!,
                                  width: 2,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: category.color.withOpacity(
                                            0.5,
                                          ),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    category.emoji,
                                    style: TextStyle(
                                      fontSize: isSelected ? 26 : 22,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                  ),
                                ),
                              ),
                            ),
                            if (unseenCount > 0)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.black,
                                      width: 2,
                                    ),
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 20,
                                    minHeight: 20,
                                  ),
                                  child: Center(
                                    child: Text(
                                      unseenCount > 9 ? '9+' : '$unseenCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Card widget ──────────────────────────────────────────────────────────────

class QueendomGroupCard extends StatefulWidget {
  final GroupModel group;
  final Color accentColor;
  final bool hasUnseen;

  const QueendomGroupCard({
    super.key,
    required this.group,
    required this.accentColor,
    required this.hasUnseen,
  });

  @override
  State<QueendomGroupCard> createState() => _QueendomGroupCardState();
}

class _QueendomGroupCardState extends State<QueendomGroupCard>
    with TickerProviderStateMixin {
  AnimationController? _animationController;
  Animation<double>? _opacityAnimation;

  Color get _safeAccentColor {
    final hsl = HSLColor.fromColor(widget.accentColor);
    if (hsl.lightness < 0.25) {
      return hsl.withLightness(0.55).withSaturation(0.7).toColor();
    }
    return widget.accentColor;
  }

  @override
  void initState() {
    super.initState();
    if (widget.hasUnseen) {
      _animationController = AnimationController(
        duration: const Duration(milliseconds: 800),
        vsync: this,
      )..repeat(reverse: true);
      _opacityAnimation = Tween<double>(begin: 0.4, end: 0.8).animate(
        CurvedAnimation(parent: _animationController!, curve: Curves.easeInOut),
      );
    }
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _safeAccentColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GroupChatScreen(
              color: color,
              groupPic: widget.group.groupPic,
              chatBackgroundUrl: widget.group.chatBackgroundUrl,
              name: widget.group.name,
              groupId: widget.group.groupId,
              fcmToken: List<String>.from(widget.group.fcmTokens ?? []),
              membersUid: List<String>.from(widget.group.membersUid ?? []),
              wish: widget.group.wish,
              queendom: widget.group.queendom,
              type: "queenPooja",
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(16),
        child: widget.hasUnseen
            ? AnimatedBuilder(
                animation: _opacityAnimation!,
                builder: (context, child) => Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: color.withOpacity(_opacityAnimation!.value),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(
                          _opacityAnimation!.value * 0.5,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: child,
                ),
                child: _buildCardContent(color),
              )
            : Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withOpacity(0.4), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _buildCardContent(color),
              ),
      ),
    );
  }

  Widget _buildCardContent(Color color) {
    return Row(
      children: [
        Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: CircleAvatar(
                backgroundImage: NetworkImage(widget.group.groupPic),
                radius: 32,
                backgroundColor: Colors.grey[800],
                onBackgroundImageError: (_, __) {},
              ),
            ),
            if (widget.hasUnseen)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.group.name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: widget.hasUnseen
                      ? FontWeight.bold
                      : FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              if (widget.group.family != null &&
                  widget.group.family!.isNotEmpty &&
                  widget.group.family != 'None')
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withOpacity(0.7), width: 1),
                  ),
                  child: Text(
                    '${widget.group.family} Family',
                    style: TextStyle(
                      fontSize: 12,
                      color: HSLColor.fromColor(
                        color,
                      ).withLightness(0.65).withSaturation(0.6).toColor(),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Icon(Icons.arrow_forward_ios, size: 18, color: color.withOpacity(0.7)),
      ],
    );
  }
}

// ── Category data model ──────────────────────────────────────────────────────

class _CategoryData {
  final String title;
  final String position;
  final Color color;
  final String emoji;

  _CategoryData(this.title, this.position, this.color, this.emoji);
}
