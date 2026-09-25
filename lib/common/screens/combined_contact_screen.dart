import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/chat/screens/one_to_one_chat_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:worship_chat/features/status/controller/status_controller.dart';
import 'package:worship_chat/features/status/screens/view_status_screen.dart';
import 'package:worship_chat/features/status/screens/confirm_status_screen.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/user_model.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';

class CombinedContactsScreen extends ConsumerWidget {
  final bool isAllChats;
  const CombinedContactsScreen({super.key, required this.isAllChats});

  /// Returns the index of the first status in [statuses] that the current
  /// user has NOT seen yet. Falls back to 0 if all are seen.
  int _firstUnseenIndex(
    List<Map<String, dynamic>> statuses,
    String currentUserUid,
  ) {
    for (int i = 0; i < statuses.length; i++) {
      final seenBy = Map<String, dynamic>.from(
        statuses[i]['seenBy'] as Map? ?? {},
      );
      if (!seenBy.containsKey(currentUserUid)) return i;
    }
    // All seen — start from the beginning so the user can re-watch
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(statusStreamProvider);
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Read current user's profile pic from Hive (same source as HomeScreen)
    final currentUserProfilePic =
        Hive.box<UserModel>('userBox').get('currentUser')?.profilePic ?? '';

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status / Stories row ───────────────────────────────────
            statusAsync.when(
              data: (statuses) {
                // Group by uid
                final Map<String, List<Map<String, dynamic>>> userStatusMap =
                    {};
                for (var s in statuses) {
                  userStatusMap
                      .putIfAbsent(s['uid'] as String, () => [])
                      .add(s);
                }

                // Sort: contacts with unseen stories first, then by most recent status
                final grouped = userStatusMap.entries.toList()
                  ..sort((a, b) {
                    final aStatuses = a.value;
                    final bStatuses = b.value;
                    final aAllSeen = aStatuses.every(
                      (s) => (s['seenBy'] as Map? ?? {}).containsKey(
                        currentUserUid,
                      ),
                    );
                    final bAllSeen = bStatuses.every(
                      (s) => (s['seenBy'] as Map? ?? {}).containsKey(
                        currentUserUid,
                      ),
                    );
                    // Unseen first
                    if (!aAllSeen && bAllSeen) return -1;
                    if (aAllSeen && !bAllSeen) return 1;
                    // Then most recent last-status first
                    final aTime = (aStatuses.last['timeCreated'] as Timestamp)
                        .toDate();
                    final bTime = (bStatuses.last['timeCreated'] as Timestamp)
                        .toDate();
                    return bTime.compareTo(aTime);
                  });

                // Pull out the current user's own statuses if any
                final myStatuses = userStatusMap[currentUserUid] ?? [];
                final hasMyStatus = myStatuses.isNotEmpty;

                // Other contacts only (exclude current user from story strip)
                final otherStatuses = grouped
                    .where((e) => e.key != currentUserUid)
                    .toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 108,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        itemCount: otherStatuses.length + 1,
                        itemBuilder: (context, index) {
                          // ── Slot 0: My Status ──────────────────────────
                          if (index == 0) {
                            return _MyStatusCard(
                              hasStatus: hasMyStatus,
                              myStatuses: myStatuses,
                              currentUserProfilePic: currentUserProfilePic,
                              onAdd: () => _pickAndOpenMedia(context),
                              onView: () => Navigator.pushNamed(
                                context,
                                ViewStatusesScreen.routeName,
                                arguments: {
                                  "statuses": myStatuses,
                                  // Own statuses always start from 0
                                  "initialIndex": 0,
                                },
                              ),
                            );
                          }

                          // ── Contact story ──────────────────────────────
                          final entry = otherStatuses[index - 1];
                          final userStatuses = entry.value;
                          final latest = userStatuses.last;
                          final total = userStatuses.length;
                          final seen = userStatuses.where((s) {
                            final seenBy = Map<String, dynamic>.from(
                              s['seenBy'] as Map? ?? {},
                            );
                            return seenBy.containsKey(currentUserUid);
                          }).length;

                          // ✅ Start from first unseen status
                          final initialIndex = _firstUnseenIndex(
                            userStatuses,
                            currentUserUid,
                          );

                          return _ContactStoryCard(
                            profilePic: latest['profilePic'] as String,
                            userName: latest['userName'] as String,
                            segmentCount: total,
                            seenCount: seen,
                            isVideo:
                                (latest['mediaType'] as String?) == 'video',
                            onTap: () => Navigator.pushNamed(
                              context,
                              ViewStatusesScreen.routeName,
                              arguments: {
                                "statuses": userStatuses,
                                // ✅ Jump straight to first unseen
                                "initialIndex": initialIndex,
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    Divider(
                      color: Colors.grey.withOpacity(0.12),
                      thickness: 1,
                      indent: 14,
                      endIndent: 14,
                    ),
                  ],
                );
              },
              loading: () => const StatusRowSkeleton(),
              error: (e, _) => const SizedBox.shrink(),
            ),

            // ── Chats list ─────────────────────────────────────────────
            StreamBuilder<List<ChatContact>>(
              initialData: ref
                  .watch(chatControllerProvider)
                  .getCachedContacts(isAllChats: isAllChats),
              stream: isAllChats
                  ? ref.watch(chatControllerProvider).fetchAllContacts()
                  : ref.watch(chatControllerProvider).chatContacts(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    (!snapshot.hasData || snapshot.data!.isEmpty)) {
                  return const ContactListSkeleton();
                }
                if (!snapshot.hasData ||
                    snapshot.data == null ||
                    snapshot.data!.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text("No Chats Found")),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final chat = snapshot.data![index];
                    final pic = chat.profilePic;
                    final hasUnread =
                        chat.unseenCount != null && chat.unseenCount != false;

                    return InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OneToOneChatScreen(
                            name: chat.name,
                            uid: chat.uid,
                            fcmToken: chat.fcmToken ?? "",
                            unseenCount: chat.unseenCount,
                            profilePic: chat.profilePic,
                            chatBackgroundUrl: chat.chatBackgroundUrl,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: pic != null
                                  ? () => _showProfilePicDialog(
                                      context,
                                      pic,
                                      chat.name,
                                      chat.uid,
                                    )
                                  : null,
                              child: Hero(
                                tag: 'profile_pic_${chat.uid}',
                                child: UserAvatar(url: pic, radius: 27),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    chat.name,
                                    style: TextStyle(
                                      fontWeight: hasUnread
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    chat.lastMessage ?? "",
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: hasUnread
                                          ? Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.color
                                                ?.withOpacity(0.7)
                                          : Colors.grey,
                                      fontWeight: hasUnread
                                          ? FontWeight.w500
                                          : FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  chat.timeSent != null
                                      ? DateFormat.jm().format(chat.timeSent!)
                                      : '',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: hasUnread ? tabColor : Colors.grey,
                                    fontWeight: hasUnread
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                                if (hasUnread) ...[
                                  const SizedBox(height: 5),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: tabColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Profile pic full-screen preview ────────────────────────────────────────

  void _showProfilePicDialog(
    BuildContext context,
    String url,
    String name,
    String uid,
  ) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Hero(
              tag: 'profile_pic_$uid',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  url,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, prog) => prog == null
                      ? child
                      : Container(
                          height: 300,
                          color: Colors.white10,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white54,
                              strokeWidth: 1.5,
                            ),
                          ),
                        ),
                  errorBuilder: (_, __, ___) => Container(
                    height: 200,
                    color: Colors.white10,
                    child: const Icon(
                      Icons.person,
                      color: Colors.white30,
                      size: 60,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text(
                  "Close",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── WhatsApp-style media picker bottom sheet ─────────────────────────────

  Future<void> _pickAndOpenMedia(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _StatusPickerSheet(
        onFilePicked: (File file, bool isVideo) {
          if (!context.mounted) return;
          Navigator.pushNamed(
            context,
            ConfirmStatusScreen.routeName,
            arguments: {'file': file, 'isVideo': isVideo},
          );
        },
      ),
    );
  }
}

// ── My Status card ──────────────────────────────────────────────────────────

class _MyStatusCard extends StatelessWidget {
  final bool hasStatus;
  final List<Map<String, dynamic>> myStatuses;
  final String currentUserProfilePic;
  final VoidCallback onAdd;
  final VoidCallback onView;

  const _MyStatusCard({
    required this.hasStatus,
    required this.myStatuses,
    required this.currentUserProfilePic,
    required this.onAdd,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: hasStatus ? onAdd : null,
      onTap: hasStatus ? onView : onAdd,
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            SizedBox(
              width: 68,
              height: 68,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: hasStatus
                          ? Border.all(color: tabColor, width: 2.5)
                          : Border.all(
                              color: Colors.grey.withOpacity(0.35),
                              width: 1.5,
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(3),
                    child: ClipOval(
                      child: hasStatus
                          ? Image.network(
                              myStatuses.last['statusUrl'] as String,
                              width: 62,
                              height: 62,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholder(),
                            )
                          : _placeholder(),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: onAdd,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: tabColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "My Story",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: tabColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return UserAvatar(
      url: currentUserProfilePic.isNotEmpty ? currentUserProfilePic : null,
      radius: 31,
    );
  }
}

// ── Contact story card ──────────────────────────────────────────────────────

class _ContactStoryCard extends StatelessWidget {
  final String profilePic;
  final String userName;
  final int segmentCount;
  final int seenCount;
  final bool isVideo;
  final VoidCallback onTap;

  const _ContactStoryCard({
    required this.profilePic,
    required this.userName,
    required this.segmentCount,
    required this.seenCount,
    required this.isVideo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final allSeen = seenCount == segmentCount;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            SizedBox(
              width: 68,
              height: 68,
              child: CustomPaint(
                painter: _RingPainter(
                  segments: segmentCount,
                  seen: seenCount,
                  unseenColor: tabColor,
                  seenColor: Colors.grey.shade400,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3.5),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: profilePic,
                          width: 61,
                          height: 61,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 61,
                            height: 61,
                            color: tabColor.withOpacity(0.08),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            width: 61,
                            height: 61,
                            color: tabColor.withOpacity(0.1),
                            child: Icon(
                              Icons.person,
                              color: tabColor,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                      if (isVideo)
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              userName,
              style: TextStyle(
                fontSize: 11,
                fontWeight: allSeen ? FontWeight.w400 : FontWeight.w600,
                color: allSeen ? Colors.grey : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── WhatsApp-style status picker sheet ─────────────────────────────────────

class _StatusPickerSheet extends StatelessWidget {
  final void Function(File file, bool isVideo) onFilePicked;

  const _StatusPickerSheet({required this.onFilePicked});

  Future<void> _pickFromCamera(BuildContext context) async {
    Navigator.pop(context);
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CameraTypeSheet(onFilePicked: onFilePicked),
    );
  }

  Future<void> _pickFromGallery(BuildContext context) async {
    Navigator.pop(context);
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _GalleryTypeSheet(onFilePicked: onFilePicked),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1F1F1F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add to status',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _PickerOption(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  color: const Color(0xFF00BFA5),
                  onTap: () => _pickFromCamera(context),
                ),
                _PickerOption(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  color: const Color(0xFF7C4DFF),
                  onTap: () => _pickFromGallery(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Camera type picker (Photo vs Video) ────────────────────────────────────

class _CameraTypeSheet extends StatelessWidget {
  final void Function(File file, bool isVideo) onFilePicked;

  const _CameraTypeSheet({required this.onFilePicked});

  Future<void> _takePhoto(BuildContext context) async {
    Navigator.pop(context);
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (picked == null) return;
    onFilePicked(File(picked.path), false);
  }

  Future<void> _recordVideo(BuildContext context) async {
    Navigator.pop(context);
    final picked = await ImagePicker().pickVideo(source: ImageSource.camera);
    if (picked == null) return;
    onFilePicked(File(picked.path), true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1F1F1F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Camera',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _PickerOption(
                  icon: Icons.photo_camera_rounded,
                  label: 'Photo',
                  color: const Color(0xFF00BFA5),
                  onTap: () => _takePhoto(context),
                ),
                _PickerOption(
                  icon: Icons.videocam_rounded,
                  label: 'Video',
                  color: const Color(0xFFE53935),
                  onTap: () => _recordVideo(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Gallery type picker (Photo vs Video) ───────────────────────────────────

class _GalleryTypeSheet extends StatelessWidget {
  final void Function(File file, bool isVideo) onFilePicked;

  const _GalleryTypeSheet({required this.onFilePicked});

  Future<void> _pickPhoto(BuildContext context) async {
    Navigator.pop(context);
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null) return;
    onFilePicked(File(picked.path), false);
  }

  Future<void> _pickVideo(BuildContext context) async {
    Navigator.pop(context);
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    onFilePicked(File(picked.path), true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1F1F1F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Gallery',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _PickerOption(
                  icon: Icons.photo_library_rounded,
                  label: 'Photo',
                  color: const Color(0xFF7C4DFF),
                  onTap: () => _pickPhoto(context),
                ),
                _PickerOption(
                  icon: Icons.video_library_rounded,
                  label: 'Video',
                  color: const Color(0xFFE53935),
                  onTap: () => _pickVideo(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Reusable picker option tile ─────────────────────────────────────────────

class _PickerOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PickerOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.4), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Segmented ring painter ──────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final int segments;
  final int seen;
  final Color unseenColor;
  final Color seenColor;

  _RingPainter({
    required this.segments,
    required this.seen,
    required this.unseenColor,
    required this.seenColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 2;

    Paint p(Color col) => Paint()
      ..color = col
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (segments <= 1) {
      canvas.drawCircle(c, r, p(seen >= 1 ? seenColor : unseenColor));
      return;
    }
    final gap = 5.0 / r;
    final seg = (2 * math.pi - gap * segments) / segments;
    for (int i = 0; i < segments; i++) {
      final start = -math.pi / 2 + (seg + gap) * i;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        seg,
        false,
        p(i < seen ? seenColor : unseenColor),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.segments != segments || o.seen != seen;
}
