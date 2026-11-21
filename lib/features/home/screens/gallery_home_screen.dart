import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/bookmark/screens/bookmark_screen.dart';
import 'package:worship_chat/features/group/screens/folder_gallery_screen.dart';
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
  final bool showAppBar;
  const GalleryHomeScreen({super.key, this.showAppBar = true});

  @override
  ConsumerState<GalleryHomeScreen> createState() => _GalleryHomeScreenState();
}

class _GalleryHomeScreenState extends ConsumerState<GalleryHomeScreen> {
  String _search = '';
  String _category = 'All';

  Future<void> _logout() async {
    if (Hive.isBoxOpen('userBox')) {
      await Hive.box<UserModel>('userBox').delete('currentUser');
    }
    if (mounted) ref.read(authControllerProvider).logout(context);
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
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
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
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.folder_open_rounded, size: 16),
                          label: const Text('Open Folder / ZIP'),
                          onPressed: () =>
                              FolderGalleryScreen.showPickerOptions(context),
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
                      ...['All', 'Queen Pooja', 'Queen Rashmika', 'General']
                          .map(
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
                    ],
                  ),
                ),
                const SizedBox(height: 12),
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
                        final general =
                            group.queendom == null ||
                            group.queendom == 'None' ||
                            group.queendom!.isEmpty;
                        final matchesCategory =
                            _category == 'All' ||
                            (_category == 'General'
                                ? general
                                : group.queendom == _category);
                        final matchesSearch =
                            '${group.name} ${group.effectiveLivingPlace} ${group.parentGroupName ?? ''}'
                                .toLowerCase()
                                .contains(_search);
                        return matchesCategory && matchesSearch;
                      }).toList();
                      if (filtered.isEmpty) {
                        return Center(
                          child: Text(
                            groups.isEmpty
                                ? 'Your group galleries will appear here.'
                                : 'No galleries match your search.',
                          ),
                        );
                      }
                      return GridView.builder(
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
        title: const Text('Worship Gallery'),
        actions: [
          IconButton(
            tooltip: 'Open Folder / ZIP',
            icon: const Icon(Icons.folder_open_rounded),
            onPressed: () => FolderGalleryScreen.showPickerOptions(context),
          ),
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
          IconButton(
            tooltip: 'Bookmarks',
            icon: const Icon(Icons.bookmark_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BookmarkScreen()),
            ),
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
              } else if (value == 'folder') {
                FolderGalleryScreen.showPickerOptions(context);
              } else {
                _logout();
              }
            },
            itemBuilder: (_) => [
              _buildGalleryMenuItem(
                value: 'folder',
                icon: Icons.folder_open_rounded,
                color: tabColor,
                title: 'Open Folder',
              ),
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
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              UserAvatar(url: group.groupPic, radius: 36),
              const SizedBox(height: 12),
              Text(
                group.nameWithPosition,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                '${group.galleryCount} photos',
                style: const TextStyle(color: greyColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
