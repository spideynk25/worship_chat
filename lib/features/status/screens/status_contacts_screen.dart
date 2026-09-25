import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/features/status/controller/status_controller.dart';
import 'package:worship_chat/features/status/screens/view_status_screen.dart';

class StatusContactsScreen extends ConsumerWidget {
  const StatusContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(statusStreamProvider);

    return Scaffold(
      body: statusAsync.when(
        data: (statuses) {
          // Group statuses by uid
          final Map<String, List<Map<String, dynamic>>> userStatusMap = {};

          for (var status in statuses) {
            final uid = status['uid'];
            if (!userStatusMap.containsKey(uid)) {
              userStatusMap[uid] = [];
            }
            userStatusMap[uid]!.add(status);
          }

          final groupedStatuses = userStatusMap.entries.toList();

          return ListView.builder(
            itemCount: groupedStatuses.length,
            itemBuilder: (context, index) {
              final userStatuses = groupedStatuses[index].value;
              final latestStatus = userStatuses.last;

              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: NetworkImage(latestStatus['profilePic']),
                ),
                title: Text(latestStatus['userName']),
                subtitle: Text(
                  "${userStatuses.length} status${userStatuses.length > 1 ? 'es' : ''}",
                ),
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    ViewStatusesScreen.routeName,
                    arguments: {"statuses": userStatuses, "initialIndex": 0},
                  );
                },
              );
            },
          );
        },
        loading: () => const StatusListSkeleton(),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Uint8List _decodeBase64(String base64String) {
    // Remove data:image/...;base64, if present
    final cleaned =
        base64String.contains(',')
            ? base64String.split(',').last
            : base64String;
    return base64Decode(cleaned);
  }
}
