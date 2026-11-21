import 'package:flutter/material.dart';

class ChatUnavailableScreen extends StatelessWidget {
  const ChatUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Worship Gallery')),
    body: const Center(child: Text('Chat is available on phones.')),
  );
}
