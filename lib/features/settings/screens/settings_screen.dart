import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/settings/screens/display_settings_screen.dart';
import 'package:worship_chat/features/settings/screens/queendom_management_screen.dart';
import 'package:worship_chat/models/user_model.dart';

class SettingsScreen extends StatelessWidget {
  static const routeName = '/settings-screen';

  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161426),
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF161426),
              Color(0xFF0F0E17),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── User Summary Card ─────────────────────────────────────────
                _buildUserProfileTile(context),

                const SizedBox(height: 24),

                // ── Section 1: Queendom Customization ─────────────────────────
                _buildSectionTitle('QUEENDOM CUSTOMIZATION'),
                const SizedBox(height: 10),
                _buildSettingsCard([
                  _buildSettingsRow(
                    icon: Icons.auto_awesome,
                    iconColor: const Color(0xFFFFD700),
                    title: 'Queendom Families & Categories',
                    subtitle: 'Add custom families, positions & group categories',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const QueendomManagementScreen(),
                        ),
                      );
                    },
                  ),
                ]),

                const SizedBox(height: 24),

                // ── Section 2: Preferences & Display ─────────────────────────
                _buildSectionTitle('PREFERENCES & APPEARANCE'),
                const SizedBox(height: 10),
                _buildSettingsCard([
                  _buildSettingsRow(
                    icon: Icons.palette_rounded,
                    iconColor: const Color(0xFF8B5CF6),
                    title: 'Display Settings',
                    subtitle: 'Chat bubble transparency, slider & preview',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DisplaySettingsScreen(),
                        ),
                      );
                    },
                  ),
                ]),

                const SizedBox(height: 24),

                // ── Section 3: App Information ───────────────────────────────
                _buildSectionTitle('ABOUT & VERSION'),
                const SizedBox(height: 10),
                _buildSettingsCard([
                  _buildSettingsRow(
                    icon: Icons.workspace_premium_rounded,
                    iconColor: const Color(0xFFFFD700),
                    title: 'Worship Chat',
                    subtitle: 'Version 2.0 • Imperial Queendom Edition',
                    showArrow: false,
                    trailing: const Text('👑', style: TextStyle(fontSize: 16)),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserProfileTile(BuildContext context) {
    if (!Hive.isBoxOpen('userBox')) {
      return _buildProfileContainer(
        context,
        displayName: 'Devotee',
        userName: '',
        email: '',
        profilePic: null,
      );
    }
    return ValueListenableBuilder(
      valueListenable: Hive.box<UserModel>('userBox').listenable(),
      builder: (context, Box<UserModel> box, _) {
        final user = box.get('currentUser');
        final displayName = user?.name ?? 'Devotee';
        final userName = user?.userName != null && user!.userName!.isNotEmpty
            ? '@${user.userName}'
            : '';
        final email = user?.email ?? '';

        return _buildProfileContainer(
          context,
          displayName: displayName,
          userName: userName,
          email: email,
          profilePic: user?.profilePic,
        );
      },
    );
  }

  Widget _buildProfileContainer(
    BuildContext context, {
    required String displayName,
    required String userName,
    required String email,
    required String? profilePic,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161426),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: tabColor.withValues(alpha: 0.8),
                width: 1.5,
              ),
            ),
            child: UserAvatar(url: profilePic, radius: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (userName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    userName,
                    style: TextStyle(
                      color: tabColor.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[400],
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161426),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.09),
          width: 0.8,
        ),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSettingsRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool showArrow = true,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: iconColor.withValues(alpha: 0.35),
                  width: 0.8,
                ),
              ),
              child: Icon(icon, size: 19, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
            if (showArrow && trailing == null)
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white38,
                size: 13,
              ),
          ],
        ),
      ),
    );
  }
}
