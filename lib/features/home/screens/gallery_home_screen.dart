import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/group/screens/duplicate_finder_screen.dart';
import 'package:worship_chat/features/group/screens/group_gallery_screen.dart';
import 'package:worship_chat/features/group/widgets/multi_gallery_shuffle_sheet.dart';
import 'package:worship_chat/features/home/screens/profile_screen.dart';
import 'package:worship_chat/features/settings/screens/settings_screen.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/user_model.dart';

final galleryGroupsProvider = StreamProvider.autoDispose<List<GroupModel>>((
  ref,
) {
  final uid = ref.watch(authStateChangesProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('groups')
      .where('membersUid', arrayContains: uid)
      .snapshots()
      .map((snapshot) {
        final groups = snapshot.docs.map((doc) {
          return GroupModel.fromMap({...doc.data(), 'groupId': doc.id});
        }).toList();
        groups.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return groups;
      });
});

/// Desktop and tablet entry point. Only gallery data is subscribed here.
class GalleryHomeScreen extends ConsumerStatefulWidget {
  static const String routeName = '/gallery-home';
  final bool showAppBar;
  final String title;

  const GalleryHomeScreen({
    super.key,
    this.showAppBar = true,
    this.title = 'Worship Gallery',
  });

  @override
  ConsumerState<GalleryHomeScreen> createState() => _GalleryHomeScreenState();
}

class _GalleryHomeScreenState extends ConsumerState<GalleryHomeScreen> {
  String _search = '';
  String _category = 'All';
  String _sortBy = 'Most Photos';
  bool _onlyWithPhotos = false;

  Future<void> _logout() async {
    if (Hive.isBoxOpen('userBox')) {
      await Hive.box<UserModel>('userBox').delete('currentUser');
    }
    if (mounted) ref.read(authControllerProvider).logout(context);
  }

  PopupMenuItem<String> _buildSortMenuItem(String label, IconData icon) {
    final isSelected = _sortBy == label;
    return PopupMenuItem<String>(
      value: label,
      height: 38,
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected ? tabColor : Colors.white70,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? tabColor : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final galleries = ref.watch(galleryGroupsProvider);
    final Widget bodyContent = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: TextField(
                  onChanged: (value) =>
                      setState(() => _search = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search galleries',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: mobileChatBoxColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    // Sort By selector
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Builder(
                        builder: (btnContext) => InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            final box = btnContext.findRenderObject() as RenderBox?;
                            final overlay = Overlay.of(btnContext).context.findRenderObject() as RenderBox?;
                            if (box == null || overlay == null) return;
                            final position = RelativeRect.fromRect(
                              Rect.fromPoints(
                                box.localToGlobal(Offset.zero, ancestor: overlay),
                                box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
                              ),
                              Offset.zero & overlay.size,
                            );
                            final selected = await showMenu<String>(
                              context: btnContext,
                              position: position,
                              color: const Color(0xFF1C182A),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  width: 0.8,
                                ),
                              ),
                              items: [
                                _buildSortMenuItem('Most Photos', Icons.arrow_downward_rounded),
                                _buildSortMenuItem('Least Photos', Icons.arrow_upward_rounded),
                                _buildSortMenuItem('Name (A-Z)', Icons.sort_by_alpha_rounded),
                                _buildSortMenuItem('Name (Z-A)', Icons.sort_by_alpha_rounded),
                              ],
                            );
                            if (selected != null) {
                              setState(() => _sortBy = selected);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: tabColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: tabColor.withValues(alpha: 0.4),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.swap_vert_rounded,
                                  size: 15,
                                  color: tabColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _sortBy,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: tabColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: const Icon(Icons.shuffle_rounded, size: 16, color: tabColor),
                        label: const Text('Multi Shuffle'),
                        onPressed: () {
                          galleries.whenData((groups) {
                            MultiGalleryShuffleSheet.show(
                              context,
                              availableGroups: groups,
                              accentColor: tabColor,
                            );
                          });
                        },
                      ),
                    ),
                    ...['All', 'Queen Pooja', 'Queen Rashmika'].map(
                      (category) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(category),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('With Photos (>0)'),
                        selected: _onlyWithPhotos,
                        onSelected: (val) =>
                            setState(() => _onlyWithPhotos = val),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: galleries.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Unable to load galleries.'),
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(galleryGroupsProvider),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  data: (groups) {
                    final filtered = groups.where((group) {
                      final matchesCategory =
                          _category == 'All' || group.queendom == _category;
                      final matchesSearch =
                          '${group.nameWithPosition} ${group.name} ${group.effectiveLivingPlace} ${group.parentGroupName ?? ''}'
                              .toLowerCase()
                              .contains(_search);
                      final matchesPhotos =
                          !_onlyWithPhotos || group.galleryCount > 0;
                      return matchesCategory && matchesSearch && matchesPhotos;
                    }).toList();

                    // Apply Sort By
                    if (_sortBy == 'Most Photos') {
                      filtered.sort((a, b) => b.galleryCount.compareTo(a.galleryCount));
                    } else if (_sortBy == 'Least Photos') {
                      filtered.sort((a, b) => a.galleryCount.compareTo(b.galleryCount));
                    } else if (_sortBy == 'Name (A-Z)') {
                      filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                    } else if (_sortBy == 'Name (Z-A)') {
                      filtered.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
                    }

                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          groups.isEmpty
                              ? 'Your group galleries will appear here.'
                              : 'No galleries match your search.',
                        ),
                      );
                    }

                    final totalFilteredPhotos = filtered.fold<int>(
                      0,
                      (total, g) => total + g.galleryCount,
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Total Count Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: tabColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: tabColor.withValues(alpha: 0.35),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  '$totalFilteredPhotos Photos',
                                  style: const TextStyle(
                                    color: tabColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'across ${filtered.length} ${filtered.length == 1 ? 'gallery' : 'galleries'}',
                                style: const TextStyle(
                                  color: greyColor,
                                  fontSize: 12,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const DuplicateFinderScreen(
                                        accentColor: tabColor,
                                      ),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.orange.withValues(alpha: 0.35),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.copy_rounded,
                                        size: 13,
                                        color: Colors.orangeAccent,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Find Duplicates',
                                        style: TextStyle(
                                          color: Colors.orangeAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 300,
                              mainAxisExtent: 220,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (_, index) =>
                                _GalleryCard(group: filtered[index]),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!widget.showAppBar) {
      return bodyContent;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Multi Gallery Shuffle',
            icon: const Icon(Icons.shuffle_rounded),
            onPressed: () {
              galleries.whenData((groups) {
                MultiGalleryShuffleSheet.show(
                  context,
                  availableGroups: groups,
                  accentColor: tabColor,
                );
              });
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            elevation: 16,
            shadowColor: Colors.black.withValues(alpha: 0.7),
            color: const Color(0xFF161426),
            surfaceTintColor: Colors.transparent,
            offset: const Offset(0, 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1.0,
              ),
            ),
            icon: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: tabColor.withValues(alpha: 0.75),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: tabColor.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              child: const Icon(Icons.account_circle, color: tabColor, size: 24),
            ),
            onSelected: (value) {
              if (value == 'profile') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              } else if (value == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              } else {
                _logout();
              }
            },
            itemBuilder: (_) => [
              _buildGalleryMenuItem(
                value: 'profile',
                icon: Icons.person_rounded,
                color: const Color(0xFF8B5CF6),
                title: 'Profile',
              ),
              _buildGalleryMenuItem(
                value: 'settings',
                icon: Icons.settings_rounded,
                color: const Color(0xFF00D2D3),
                title: 'Settings',
              ),
              _buildGalleryMenuDivider(),
              _buildGalleryMenuItem(
                value: 'logout',
                icon: Icons.logout_rounded,
                color: const Color(0xFFFF5252),
                title: 'Logout',
                textColor: const Color(0xFFFF6B6B),
              ),
            ],
          ),
        ],
      ),
      body: bodyContent,
    );
  }

  PopupMenuItem<String> _buildGalleryMenuItem({
    required String value,
    required IconData icon,
    required Color color,
    required String title,
    Color? textColor,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor ?? Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuEntry<String> _buildGalleryMenuDivider() {
    return PopupMenuItem<String>(
      enabled: false,
      height: 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Divider(
        color: Colors.white.withValues(alpha: 0.10),
        height: 1,
        thickness: 0.8,
      ),
    );
  }
}

class _GalleryCard extends StatelessWidget {
  const _GalleryCard({required this.group});
  final GroupModel group;

  @override
  Widget build(BuildContext context) {
    final accent = group.queendom == 'Queen Pooja' ? Colors.amber : tabColor;
    return Card(
      color: mobileChatBoxColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: accent.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupGalleryScreen(
              groupId: group.groupId,
              groupName: group.nameWithPosition,
              accentColor: accent,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              UserAvatar(url: group.groupPic, radius: 34),
              const SizedBox(height: 10),
              Text(
                group.nameWithPosition,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.45),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  '${group.galleryCount} photos',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
