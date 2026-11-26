import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/app_media_picker_sheet.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';

class UserInformationScreen extends ConsumerStatefulWidget {
  static const routeName = '/user-information-screen';
  const UserInformationScreen({super.key});

  @override
  ConsumerState<UserInformationScreen> createState() =>
      _UserInformationScreenState();
}

class _UserInformationScreenState extends ConsumerState<UserInformationScreen> {
  final TextEditingController nameController = TextEditingController();
  File? image;
  String? selectedImageUrl;
  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  void selectImage() {
    showProfilePicSourceSheet(
      context: context,
      onLocalFileSelected: (selectedImage) async {
        if (!mounted) return;
        setState(() {
          image = selectedImage;
          selectedImageUrl = null;
        });
      },
      onRemoteUrlSelected: (url) async {
        if (!mounted) return;
        setState(() {
          image = null;
          selectedImageUrl = url;
        });
      },
    );
  }

  void storeUserData() async {
    String name = nameController.text.trim();
    if (name.isNotEmpty) {
      ref.read(authControllerProvider).saveUserDatatoFirebase(
            context,
            name,
            image,
            profilePicUrlOverride: image == null ? selectedImageUrl : null,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  Stack(
                    children: [
                      image != null
                          ? CircleAvatar(
                              radius: 64,
                              backgroundImage: FileImage(image!),
                            )
                          : (selectedImageUrl != null
                              ? UserAvatar(
                                  url: selectedImageUrl,
                                  radius: 64,
                                  backgroundColor: greyColor,
                                )
                              : const CircleAvatar(
                                  backgroundColor: greyColor,
                                  radius: 64,
                                  child: Icon(
                                    Icons.person,
                                    color: blackColor,
                                    size: 70,
                                  ),
                                )),
                      Positioned(
                        bottom: -10,
                        left: 80,
                        child: IconButton(
                          onPressed: selectImage,
                          icon: const Icon(Icons.add_a_photo),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: TextField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              hintText: 'Enter your name',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: storeUserData,
                        icon: const Icon(Icons.done),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
