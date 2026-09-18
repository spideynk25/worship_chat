import 'package:flutter/material.dart';
import 'package:worship_chat/common/widgets/error_screen.dart';
import 'package:worship_chat/features/auth/screens/forget_password_screen.dart';
import 'package:worship_chat/features/auth/screens/login_screen.dart';
import 'package:worship_chat/features/auth/screens/register_screen.dart';
import 'package:worship_chat/features/auth/screens/user_information_screen.dart';
import 'package:worship_chat/features/chat/screens/one_to_one_chat_screen.dart';
import 'package:worship_chat/features/chat/widgets/all_user_screen.dart';
import 'package:worship_chat/features/group/screens/create_group_screen.dart';
import 'package:worship_chat/features/group/screens/edit_group_screen.dart';
import 'package:worship_chat/features/status/screens/confirm_status_screen.dart';
import 'package:worship_chat/features/status/screens/view_status_screen.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/features/dashboard/widgets/todo_page.dart';
import 'package:worship_chat/features/dashboard/screens/event_calender_page.dart';

Route<dynamic> generateRoute(RouteSettings settings) {
  switch (settings.name) {
    case LoginScreen.routeName:
      return MaterialPageRoute(builder: (context) => const LoginScreen());

    case RegisterScreen.routeName:
      return MaterialPageRoute(builder: (context) => const RegisterScreen());

    case ForgetPasswordScreen.routeName:
      return MaterialPageRoute(builder: (context) => const LoginScreen());

    case UserInformationScreen.routeName:
      return MaterialPageRoute(
        builder: (context) => const UserInformationScreen(),
      );

    case AllUserScreen.routeName:
      return MaterialPageRoute(builder: (context) => AllUserScreen());

    case ConfirmStatusScreen.routeName:
      return MaterialPageRoute(
        settings: settings,
        builder: (context) => const ConfirmStatusScreen(),
      );

    case ViewStatusesScreen.routeName:
      final arguments = settings.arguments as Map<String, dynamic>;
      return MaterialPageRoute(
        builder: (context) => ViewStatusesScreen(
          statuses: List<Map<String, dynamic>>.from(arguments['statuses']),
          initialIndex: arguments['initialIndex'] as int? ?? 0,
        ),
      );

    // ── Notification tap navigates here via senderUid data ────────────────
    case OneToOneChatScreen.routeName:
      final args = settings.arguments as Map<String, dynamic>;
      return MaterialPageRoute(
        builder: (context) => OneToOneChatScreen(
          name: args['name'] as String,
          uid: args['uid'] as String,
          fcmToken: args['fcmToken'] as String? ?? '',
          profilePic: args['profilePic'] as String?,
          unseenCount: args['unseenCount'] as bool? ?? true,
          chatBackgroundUrl: args['chatBackgroundUrl'] as String?,
        ),
      );

    case CreateGroupScreen.routeName:
      return MaterialPageRoute(builder: (context) => const CreateGroupScreen());

    case TodoPage.routeName:
      return MaterialPageRoute(builder: (context) => const TodoPage());

    case EventsCalendarPage.routeName:
      return MaterialPageRoute(
        builder: (context) => const EventsCalendarPage(),
      );

    default:
      return MaterialPageRoute(
        builder: (context) => const Scaffold(
          body: ErrorScreen(error: 'This page doesn\'t exist'),
        ),
      );
  }
}
