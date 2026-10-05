import 'dart:developer';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/screens/create_sub_group_screen.dart';
import 'package:worship_chat/features/group/screens/group_chat_screen.dart';
import 'package:worship_chat/features/group/utils/group_template_helper.dart';
import 'package:worship_chat/features/group/utils/queendom_emblem_helper.dart';
import 'package:worship_chat/features/group/widgets/royal_avatar_decoration.dart';
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
    'Velisse',
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
      initialData:
          ref.watch(groupControllerProvider).getCachedGroups('groups_pooja'),
      stream: ref.watch(groupControllerProvider).getQueenPoojaStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            (!snapshot.hasData || snapshot.data!.isEmpty)) {
          return const ContactListSkeleton(isGroup: true);
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
            .where((g) => g.position == selectedCategory.position && !g.isSubGroup)
            .toList();

        filteredGroups.sort((a, b) {
          final hasOtherFamilies =
              GroupTemplateHelper.categoryHasOtherFamilies(selectedCategory.position);
          if (!hasOtherFamilies) {
            final aPriority = a.priority ?? a.order ?? 999999;
            final bPriority = b.priority ?? b.order ?? 999999;
            if (aPriority != bPriority) {
              return aPriority.compareTo(bPriority);
            }
            return a.effectiveLivingPlace.compareTo(b.effectiveLivingPlace);
          }
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
                        QueendomEmblemWidget(
                          position: selectedCategory.position,
                          emoji: selectedCategory.emoji,
                          size: 36,
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
                              final subGroups = groups
                                  .where((g) => g.parentGroupId == group.groupId)
                                  .toList();
                              return QueendomGroupCard(
                                group: group,
                                accentColor: selectedCategory.color,
                                hasUnseen: hasUnseen,
                                subGroups: subGroups,
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
                                child: QueendomEmblemWidget(
                                  position: category.position,
                                  emoji: category.emoji,
                                  size: isSelected ? 30 : 25,
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
  final List<GroupModel> subGroups;

  const QueendomGroupCard({
    super.key,
    required this.group,
    required this.accentColor,
    required this.hasUnseen,
    this.subGroups = const [],
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
    final sortedSubGroups = List<GroupModel>.from(widget.subGroups)
      ..sort((a, b) {
        if (a.isFuckToySubGroup != b.isFuckToySubGroup) {
          return a.isFuckToySubGroup ? 1 : -1;
        }
        return a.name.compareTo(b.name);
      });

    final cardContent = _buildCardContent(color, sortedSubGroups);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: widget.hasUnseen
          ? AnimatedBuilder(
              animation: _opacityAnimation!,
              builder: (context, child) => Container(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: color.withOpacity(_opacityAnimation!.value),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(
                        _opacityAnimation!.value * 0.5,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: child,
              ),
              child: cardContent,
            )
          : Container(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(0.4), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: cardContent,
            ),
    );
  }

  Widget _buildCardContent(Color color, List<GroupModel> sortedSubGroups) {
    final wivesCount = sortedSubGroups.where((g) => !g.isFuckToySubGroup).length;
    final fuckToysCount = sortedSubGroups.where((g) => g.isFuckToySubGroup).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Top Row: Deity (Tappable to open deity chat) ───────────────
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GroupChatScreen(
                  color: color,
                  groupPic: widget.group.groupPic,
                  chatBackgroundUrl: widget.group.chatBackgroundUrl,
                  name: widget.group.nameWithPosition,
                  groupId: widget.group.groupId,
                  fcmToken: List<String>.from(widget.group.fcmTokens),
                  membersUid: List<String>.from(widget.group.membersUid),
                  wish: widget.group.wish,
                  queendom: widget.group.queendom,
                  type: "queenPooja",
                ),
              ),
            ),
            child: Row(
              children: [
                RoyalAvatarDecoration(
                  avatarRadius: 24,
                  position: widget.group.position,
                  livingPlace: widget.group.effectiveLivingPlace,
                  accentColor: color,
                  badge: QueendomFamilyEmblemHelper.buildFamilyEmblemBadge(
                    family: widget.group.family,
                    fallbackText: widget.group.effectiveLivingPlace,
                    accentColor: color,
                    size: 14.0,
                    overlayWidget: widget.hasUnseen
                        ? Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.black, width: 1.5),
                            ),
                          )
                        : null,
                  ) ??
                      (widget.hasUnseen
                          ? Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.black, width: 2),
                              ),
                            )
                          : null),
                  badgeBottomOffset: 0,
                  badgeRightOffset: 0,
                  child: CircleAvatar(
                    backgroundImage: NetworkImage(widget.group.groupPic),
                    radius: 24,
                    backgroundColor: Colors.grey[850],
                    onBackgroundImageError: (_, __) {},
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QueendomEmblemHelper.buildRichTitle(
                        title: widget.group.effectiveLivingPlace,
                        family: widget.group.family,
                        fallbackFamily: 'Main',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: widget.hasUnseen
                              ? FontWeight.bold
                              : FontWeight.w600,
                          color: Colors.white,
                        ),
                        emblemSize: 18,
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 5,
                        runSpacing: 3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (widget.group.family != null &&
                              widget.group.family!.isNotEmpty &&
                              widget.group.family != 'None')
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: color.withOpacity(0.6),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  QueendomFamilyEmblemWidget(
                                    family: widget.group.family,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${widget.group.family} Family',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: HSLColor.fromColor(color)
                                          .withLightness(0.7)
                                          .withSaturation(0.6)
                                          .toColor(),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          if (wivesCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: color.withOpacity(0.5),
                                  width: 0.7,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const QueendomEmblemWidget(
                                    position: 'Queen',
                                    size: 11,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '$wivesCount',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: HSLColor.fromColor(color)
                                          .withLightness(0.8)
                                          .toColor(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (fuckToysCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purpleAccent.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.purpleAccent.withOpacity(0.5),
                                  width: 0.7,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('🖤 ', style: TextStyle(fontSize: 9)),
                                  Text(
                                    '$fuckToysCount',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE040FB),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (sortedSubGroups.isEmpty)
                            _buildAddSubButton(color),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios, size: 14, color: color.withOpacity(0.5)),
              ],
            ),
          ),
        ),

        // ── Bottom Tray: Horizontal Sub-groups ───────────────────────────
        if (sortedSubGroups.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            height: 1,
            color: Colors.white.withOpacity(0.07),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 88,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: sortedSubGroups.length + 1,
              itemBuilder: (context, i) {
                if (i < sortedSubGroups.length) {
                  return _buildSubGroupBubble(
                    context: context,
                    subGroup: sortedSubGroups[i],
                    deityColor: color,
                    chatType: 'queenPooja',
                  );
                } else {
                  return _buildAddBubble(color);
                }
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSubGroupBubble({
    required BuildContext context,
    required GroupModel subGroup,
    required Color deityColor,
    required String chatType,
  }) {
    final isFuckToy = subGroup.isFuckToySubGroup;
    final badgeColor = isFuckToy ? const Color(0xFFE040FB) : deityColor;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final hasUnseen =
        currentUserId != null && subGroup.hasUnseenForUser(currentUserId);
    final typeLabel = isFuckToy ? 'Fuck Toy' : 'Wife';

    return Container(
      margin: const EdgeInsets.only(right: 10),
      width: 64,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GroupChatScreen(
                  color: badgeColor,
                  groupPic: subGroup.groupPic,
                  chatBackgroundUrl: subGroup.chatBackgroundUrl,
                  name: subGroup.nameWithPosition,
                  groupId: subGroup.groupId,
                  fcmToken: List<String>.from(subGroup.fcmTokens),
                  membersUid: List<String>.from(subGroup.membersUid),
                  wish: subGroup.wish,
                  queendom: subGroup.queendom,
                  type: chatType,
                ),
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: badgeColor.withOpacity(hasUnseen ? 0.9 : 0.65),
                        width: hasUnseen ? 2.0 : 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: badgeColor.withOpacity(hasUnseen ? 0.4 : 0.15),
                          blurRadius: 5,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 17,
                      backgroundImage: subGroup.groupPic.isNotEmpty
                          ? NetworkImage(subGroup.groupPic)
                          : null,
                      backgroundColor: Colors.grey[850],
                      child: subGroup.groupPic.isEmpty
                          ? const Icon(Icons.person, color: Colors.white, size: 16)
                          : null,
                    ),
                  ),
                  if (hasUnseen)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 1.5),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: -3,
                    right: -3,
                    child: Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: badgeColor.withOpacity(0.8),
                          width: 0.8,
                        ),
                      ),
                      child: isFuckToy
                          ? const Text(
                              '🖤',
                              style: TextStyle(fontSize: 8),
                            )
                          : const QueendomEmblemWidget(
                              position: 'Queen',
                              size: 10,
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subGroup.name,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.15,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 1),
              Text(
                typeLabel,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w500,
                  color: badgeColor.withOpacity(0.85),
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddBubble(Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      width: 56,
      child: PopupMenuButton<String>(
        tooltip: 'Add Sub-Group',
        color: const Color(0xFF1E1E1E),
        elevation: 8,
        offset: const Offset(0, 36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withOpacity(0.15), width: 1),
        ),
        onSelected: (type) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateSubGroupScreen(
                parentGroup: widget.group,
                initialSubGroupType: type,
              ),
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.1),
                border: Border.all(
                  color: color.withOpacity(0.4),
                  width: 1.2,
                ),
              ),
              child: Icon(Icons.add_rounded, size: 19, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              'Add',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color.withOpacity(0.9),
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              'Sub',
              style: TextStyle(
                fontSize: 8.5,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'wife',
            height: 38,
            child: Row(
              children: [
                Icon(Icons.favorite_rounded, size: 15, color: color),
                const SizedBox(width: 8),
                const Text(
                  'Add Wife',
                  style: TextStyle(fontSize: 12.5, color: Colors.white),
                ),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'fuckToy',
            height: 38,
            child: Row(
              children: [
                Icon(
                  Icons.local_fire_department_rounded,
                  size: 15,
                  color: Color(0xFFE040FB),
                ),
                SizedBox(width: 8),
                Text(
                  'Add Fuck Toy',
                  style: TextStyle(fontSize: 12.5, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddSubButton([Color? _]) {
    const primaryColor = Color(0xFFFF2D78);
    const secondaryColor = Color(0xFFE040FB);

    return PopupMenuButton<String>(
      tooltip: 'Add Sub-Group',
      padding: EdgeInsets.zero,
      color: const Color(0xFF1E1E1E),
      elevation: 8,
      offset: const Offset(0, 26),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15), width: 1),
      ),
      onSelected: (type) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreateSubGroupScreen(
              parentGroup: widget.group,
              initialSubGroupType: type,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              primaryColor,
              secondaryColor,
            ],
          ),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: const Color(0xFFFF80AB).withValues(alpha: 0.6),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.45),
              blurRadius: 6,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_rounded,
              size: 12,
              color: Colors.white,
            ),
            SizedBox(width: 3),
            Text(
              'Sub',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'wife',
          height: 38,
          child: Row(
            children: const [
              Icon(Icons.favorite_rounded, size: 15, color: primaryColor),
              SizedBox(width: 8),
              Text(
                'Add Wife',
                style: TextStyle(fontSize: 12.5, color: Colors.white),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'fuckToy',
          height: 38,
          child: Row(
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                size: 15,
                color: secondaryColor,
              ),
              SizedBox(width: 8),
              Text(
                'Add Fuck Toy',
                style: TextStyle(fontSize: 12.5, color: Colors.white),
              ),
            ],
          ),
        ),
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
