import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/Features/chat/widgets/contact_list.dart';

class AllUserScreen extends ConsumerWidget {
  static const String routeName = "/all-user-screen";
  const AllUserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(appBar: AppBar(), body: ContactList(isAllChats: true));
  }
}
