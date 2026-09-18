import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/features/group/widgets/queen_rashmika_queendom_list.dart';

class QueenRashmikaQueenScreen extends ConsumerWidget {
  const QueenRashmikaQueenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(body: QueenRashmikaQueendomList());
  }
}
