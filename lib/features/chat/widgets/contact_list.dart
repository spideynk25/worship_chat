import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/loader.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/chat/screens/one_to_one_chat_screen.dart';
import 'package:worship_chat/models/chat_contact.dart';

class ContactList extends ConsumerWidget {
  final bool isAllChats;
  const ContactList({super.key, required this.isAllChats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SingleChildScrollView(
        child: StreamBuilder<List<ChatContact>>(
          stream: isAllChats
              ? ref.watch(chatControllerProvider).fetchAllContacts()
              : ref.watch(chatControllerProvider).chatContacts(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Loader();
            }
            if (!snapshot.hasData ||
                snapshot.hasError ||
                snapshot.data == null ||
                snapshot.data!.isEmpty) {
              return Center(child: Text("No Chats Found"));
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                var chatContactData = snapshot.data![index];
                // Uint8List? profileImage;
                // if (chatContactData.profilePic != null) {
                //   profileImage = base64Decode(chatContactData.profilePic!);
                // }
                String? profileImage = chatContactData.profilePic;
                log("contact list fcm token: ${chatContactData.fcmToken}");
                return Column(
                  children: [
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => OneToOneChatScreen(
                              name: chatContactData.name,
                              uid: chatContactData.uid,
                              fcmToken: chatContactData.fcmToken ?? "",
                              unseenCount: chatContactData.unseenCount,
                              profilePic: chatContactData.profilePic,
                              chatBackgroundUrl:
                                  chatContactData.chatBackgroundUrl,
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ListTile(
                          title: Text(chatContactData.name),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              chatContactData.lastMessage ?? "",
                              style: const TextStyle(fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          leading: profileImage != null
                              ? CircleAvatar(
                                  radius: 30,
                                  backgroundImage: NetworkImage(profileImage),
                                )
                              : CircleAvatar(child: Icon(Icons.person)),
                          trailing: Column(
                            children: [
                              chatContactData.timeSent != null
                                  ? Text(
                                      DateFormat.Hm().format(
                                        chatContactData.timeSent!,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: Colors.grey,
                                      ),
                                    )
                                  : Text(""),
                              SizedBox(height: 5),
                              if (chatContactData.unseenCount != null &&
                                  chatContactData.unseenCount != false)
                                Container(
                                  padding: EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: tabColor,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text("New Message"),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Divider(color: dividerColor, indent: 85),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
