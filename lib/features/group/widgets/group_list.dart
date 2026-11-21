import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/screens/group_chat_screen.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/features/group/screens/group_gallery_screen.dart';
import 'package:worship_chat/features/group/utils/queendom_emblem_helper.dart';
import 'package:worship_chat/features/group/widgets/royal_avatar_decoration.dart';
import 'package:worship_chat/models/group.dart';
import 'dart:developer';

class GroupList extends ConsumerWidget {
  const GroupList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get current user ID safely
    final currentUserId = () {
      try {
        return FirebaseAuth.instance.currentUser?.uid;
      } catch (_) {
        return null;
      }
    }();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SingleChildScrollView(
        child: StreamBuilder<List<GroupModel>>(
          initialData: ref
              .watch(groupControllerProvider)
              .getCachedGroups('groups_none'),
          stream: ref.watch(groupControllerProvider).chatGroups(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                (!snapshot.hasData || snapshot.data!.isEmpty)) {
              return const ContactListSkeleton(isGroup: true);
            }
            if (snapshot.hasError) {
              log('Stream error: ${snapshot.error}');
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text("No Chats Found"));
            }
            final groups = snapshot.data!;
            log('Displaying ${groups.length} groups');

            // Separate groups into unseen and seen for better UX
            final unseenGroups = <GroupModel>[];
            final seenGroups = <GroupModel>[];

            for (var group in groups) {
              if (currentUserId != null &&
                  group.hasUnseenForUser(currentUserId)) {
                unseenGroups.add(group);
              } else {
                seenGroups.add(group);
              }
            }

            // Combine with unseen first
            final sortedGroups = [...unseenGroups, ...seenGroups];

            return Column(
              children: [
                // Unseen message count banner (optional)
                if (unseenGroups.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          tabColor.withValues(alpha: 0.3),
                          tabColor.withValues(alpha: 0.1),
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${unseenGroups.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          unseenGroups.length == 1
                              ? '1 group with new messages'
                              : '${unseenGroups.length} groups with new messages',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: sortedGroups.length,
                  itemBuilder: (context, index) {
                    var groupChatListData = sortedGroups[index];
                    String? profileImage = groupChatListData.groupPic;

                    // Check if CURRENT USER has unseen messages
                    final hasUnseenForCurrentUser =
                        currentUserId != null &&
                        groupChatListData.hasUnseenForUser(currentUserId);

                    log(
                      'Group: ${groupChatListData.name}, User: $currentUserId, HasUnseen: $hasUnseenForCurrentUser',
                    );

                    return Column(
                      children: [
                        InkWell(
                          onTap: () {
                            log(
                              'Navigating to group: ${groupChatListData.groupId}',
                            );
                            if (!AppCapabilities.current.chatEnabled) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => GroupGalleryScreen(
                                    groupId: groupChatListData.groupId,
                                    groupName: groupChatListData.nameWithPosition,
                                    accentColor: tabColor,
                                  ),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => GroupChatScreen(
                                    groupPic: groupChatListData.groupPic,
                                    chatBackgroundUrl:
                                        groupChatListData.chatBackgroundUrl,
                                    name: groupChatListData.nameWithPosition,
                                    groupId: groupChatListData.groupId,
                                    fcmToken:
                                        groupChatListData.fcmTokens,
                                    membersUid:
                                        groupChatListData.membersUid,
                                    wish: groupChatListData.wish,
                                    queendom: groupChatListData.queendom,
                                    color: null,
                                    type: "others",
                                  ),
                                ),
                              );
                            }
                          },
                          child: Container(
                            // Add subtle background for unseen messages
                            color: (hasUnseenForCurrentUser && AppCapabilities.current.chatEnabled)
                                ? tabColor.withValues(alpha: 0.05)
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child:
                                          QueendomEmblemHelper.buildRichTitle(
                                        title: groupChatListData
                                            .effectiveLivingPlace,
                                        family: groupChatListData.family,
                                        fallbackFamily: 'Main',
                                        style: TextStyle(
                                          fontWeight: hasUnseenForCurrentUser
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          fontSize: 16,
                                        ),
                                        emblemSize: 18,
                                      ),
                                    ),
                                    // Unread indicator dot next to name
                                    if (hasUnseenForCurrentUser && AppCapabilities.current.chatEnabled)
                                      Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: tabColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    AppCapabilities.current.chatEnabled
                                        ? groupChatListData.lastMessage
                                        : '${groupChatListData.galleryCount} photos',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: (hasUnseenForCurrentUser && AppCapabilities.current.chatEnabled)
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: (hasUnseenForCurrentUser && AppCapabilities.current.chatEnabled)
                                          ? Colors.white.withValues(alpha: 0.9)
                                          : greyColor,
                                    ),
                                  ),
                                ),
                                leading: Builder(
                                  builder: (context) {
                                    final isWifeOrToy = groupChatListData.isWifeSubGroup ||
                                        groupChatListData.isFuckToySubGroup ||
                                        QueendomEmblemHelper.isWifeOrFuckToy(groupChatListData.position) ||
                                        QueendomEmblemHelper.isWifeOrFuckToy(groupChatListData.effectiveLivingPlace) ||
                                        QueendomEmblemHelper.isWifeOrFuckToy(groupChatListData.name);
                                    return RoyalAvatarDecoration(
                                      avatarRadius: 26,
                                      isWifeOrFuckToy: isWifeOrToy,
                                      position: isWifeOrToy ? null : groupChatListData.position,
                                      livingPlace: isWifeOrToy ? null : groupChatListData.effectiveLivingPlace,
                                      accentColor: tabColor,
                                      badge: isWifeOrToy
                                          ? ((hasUnseenForCurrentUser && AppCapabilities.current.chatEnabled)
                                              ? Container(
                                                  width: 14,
                                                  height: 14,
                                                  decoration: BoxDecoration(
                                                    color: Colors.red,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: backgroundColor,
                                                      width: 2,
                                                    ),
                                                  ),
                                                )
                                              : null)
                                          : (QueendomFamilyEmblemHelper.buildFamilyEmblemBadge(
                                              family: groupChatListData.family,
                                              fallbackText:
                                                  groupChatListData.effectiveLivingPlace,
                                              accentColor: tabColor,
                                              size: 14.0,
                                              overlayWidget: (hasUnseenForCurrentUser && AppCapabilities.current.chatEnabled)
                                                  ? Container(
                                                      width: 9,
                                                      height: 9,
                                                      decoration: BoxDecoration(
                                                        color: Colors.redAccent,
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                          color: backgroundColor,
                                                          width: 1.5,
                                                        ),
                                                      ),
                                                    )
                                                  : null,
                                            ) ??
                                            ((hasUnseenForCurrentUser && AppCapabilities.current.chatEnabled)
                                                ? Container(
                                                    width: 14,
                                                    height: 14,
                                                    decoration: BoxDecoration(
                                                      color: Colors.red,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: backgroundColor,
                                                        width: 2,
                                                      ),
                                                    ),
                                                  )
                                                : null)),
                                      badgeBottomOffset: 0,
                                      badgeRightOffset: 0,
                                      child: profileImage.isNotEmpty
                                          ? CircleAvatar(
                                              radius: 26,
                                              backgroundImage: NetworkImage(profileImage),
                                              onBackgroundImageError: (error, stackTrace) {
                                                log('Error loading profile image: $error');
                                              },
                                            )
                                          : const CircleAvatar(
                                              radius: 26,
                                              child: Icon(Icons.group),
                                            ),
                                    );
                                  },
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (groupChatListData.timeSent != null)
                                      Text(
                                        DateFormat.Hm().format(
                                          groupChatListData.timeSent!,
                                        ),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: hasUnseenForCurrentUser
                                              ? tabColor
                                              : greyColor,
                                          fontWeight: hasUnseenForCurrentUser
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    const SizedBox(height: 6),
                                    // "New" badge for unseen messages
                                    if (hasUnseenForCurrentUser)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tabColor,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: tabColor.withValues(alpha: 0.3),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: const Text(
                                          "NEW",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Divider(color: dividerColor, indent: 85),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
