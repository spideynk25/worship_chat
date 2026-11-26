import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:extended_image/extended_image.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/app_media_picker_sheet.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/settings/screens/settings_screen.dart';
import 'package:worship_chat/models/user_model.dart';

enum _UsernameStatus { none, checking, available, taken, invalidSpaces }

class ProfileScreen extends ConsumerStatefulWidget {
  static const routeName = '/profile-screen';
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  File? _selectedImage;
  String? _selectedImageUrl;
  bool _removePhotoRequested = false;
  bool _isLoading = false;
  String _initialName = '';
  String _initialUserName = '';
  Timer? _usernameCheckTimer;
  _UsernameStatus _usernameStatus = _UsernameStatus.none;

  @override
  void initState() {
    super.initState();
    if (Hive.isBoxOpen('userBox')) {
      final user = Hive.box<UserModel>('userBox').get('currentUser');
      if (user != null) {
        _initialUserName = user.userName ?? '';
        _initialName = user.name ?? '';
        _userNameController.text = _initialUserName;
        _nameController.text = _initialName;
      }
    }
    _userNameController.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _usernameCheckTimer?.cancel();
    _userNameController.removeListener(_onUsernameChanged);
    _userNameController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges =>
      _selectedImage != null ||
      _selectedImageUrl != null ||
      _removePhotoRequested ||
      _nameController.text.trim() != _initialName.trim() ||
      _userNameController.text.trim() != _initialUserName.trim();

  void _onUsernameChanged() {
    _usernameCheckTimer?.cancel();
    final raw = _userNameController.text;
    final trimmed = raw.trim();

    if (RegExp(r'\s').hasMatch(trimmed)) {
      if (_usernameStatus != _UsernameStatus.invalidSpaces) {
        setState(() => _usernameStatus = _UsernameStatus.invalidSpaces);
      }
      return;
    }

    if (trimmed.isEmpty || trimmed == _initialUserName.trim()) {
      if (_usernameStatus != _UsernameStatus.none) {
        setState(() => _usernameStatus = _UsernameStatus.none);
      }
      return;
    }

    if (Firebase.apps.isEmpty) {
      if (_usernameStatus != _UsernameStatus.none) {
        setState(() => _usernameStatus = _UsernameStatus.none);
      }
      return;
    }

    setState(() => _usernameStatus = _UsernameStatus.checking);
    _usernameCheckTimer = Timer(const Duration(milliseconds: 450), () {
      _checkUsernameAvailability(trimmed);
    });
  }

  Future<void> _checkUsernameAvailability(String candidate) async {
    try {
      final currentUid = Hive.isBoxOpen('userBox')
          ? Hive.box<UserModel>('userBox').get('currentUser')?.uid
          : null;
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('userName', isEqualTo: candidate)
          .limit(1)
          .get();

      if (!mounted || _userNameController.text.trim() != candidate) return;
      final takenByOther =
          snap.docs.isNotEmpty && snap.docs.first.id != currentUid;
      setState(() {
        _usernameStatus =
            takenByOther ? _UsernameStatus.taken : _UsernameStatus.available;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _usernameStatus = _UsernameStatus.none);
    }
  }

  Future<File?> _cropImage(File imageFile) async {
    try {
      final croppedFile = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CropImageScreen(imageFile: imageFile),
        ),
      );
      return croppedFile as File?;
    } catch (e) {
      debugPrint('Crop error: $e');
      return null;
    }
  }

  Future<File?> _resizeImage(
    File imageFile, {
    int width = 256,
    int height = 256,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final resizedImage = img.copyResize(image, width: width, height: height);
      final tempDir = await getTemporaryDirectory();
      final resizedFile = File(
        '${tempDir.path}/resized_${imageFile.path.split('/').last}',
      );
      await resizedFile.writeAsBytes(img.encodeJpg(resizedImage));
      return resizedFile;
    } catch (e) {
      debugPrint('Resize error: $e');
      return null;
    }
  }

  Future<void> _applyPickedLocalFile(File pickedImage) async {
    try {
      final cropped = await _cropImage(pickedImage);
      if (!mounted || cropped == null) return;
      final resized = await _resizeImage(cropped);
      if (!mounted || resized == null) return;
      setState(() {
        _selectedImage = resized;
        _selectedImageUrl = null;
        _removePhotoRequested = false;
      });
    } catch (e) {
      debugPrint('Image picking error: $e');
    }
  }

  bool _hasActivePhoto(UserModel? user) {
    if (_removePhotoRequested) return false;
    if (_selectedImage != null && _selectedImage!.existsSync()) return true;
    if (_selectedImageUrl != null && _selectedImageUrl!.trim().isNotEmpty) {
      return true;
    }
    return UserAvatar.sanitizeUrl(user?.profilePic) != null;
  }

  void _openFullScreenPhoto(UserModel? user) {
    final hasFile = _selectedImage != null && _selectedImage!.existsSync();
    final url = _removePhotoRequested
        ? null
        : (_selectedImageUrl ?? UserAvatar.sanitizeUrl(user?.profilePic));
    if (!hasFile && url == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AvatarFullScreenViewer(
          heroTag: user?.uid ?? 'default_profile_tag',
          imageFile: hasFile ? _selectedImage : null,
          imageUrl: hasFile ? null : url,
        ),
      ),
    );
  }

  void _showAvatarOptions(UserModel? user) {
    final hasPhoto = _hasActivePhoto(user);
    showProfilePicSourceSheet(
      context: context,
      hasPhoto: hasPhoto,
      onViewPhoto: hasPhoto ? () => _openFullScreenPhoto(user) : null,
      onRemovePhoto: hasPhoto
          ? () {
              setState(() {
                _selectedImage = null;
                _selectedImageUrl = null;
                _removePhotoRequested = true;
              });
            }
          : null,
      onLocalFileSelected: _applyPickedLocalFile,
      onRemoteUrlSelected: (url) async {
        if (!mounted) return;
        setState(() {
          _selectedImage = null;
          _selectedImageUrl = url;
          _removePhotoRequested = false;
        });
      },
    );
  }

  void _discardUnsavedChanges() {
    FocusScope.of(context).unfocus();
    setState(() {
      _nameController.text = _initialName;
      _userNameController.text = _initialUserName;
      _selectedImage = null;
      _selectedImageUrl = null;
      _removePhotoRequested = false;
      _usernameStatus = _UsernameStatus.none;
    });
  }

  Future<void> _copyUsername(String handle) async {
    await Clipboard.setData(ClipboardData(text: '@$handle'));
    if (!mounted) return;
    AppSnackBar.success(context, 'Copied @$handle');
  }

  Future<void> _confirmPasswordReset(String email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF161426),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        title: const Text(
          'Reset Password',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Send a password reset link to $email?',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text(
              'Send Link',
              style: TextStyle(color: tabColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ref.read(authControllerProvider).resetPassword(context, email);
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF161426),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        title: const Text(
          'Sign Out',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to log out of Worship Chat on this device?',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text(
              'Sign Out',
              style: TextStyle(
                color: Color(0xFFFF6B6B),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ref.read(authControllerProvider).logout(context);
    }
  }

  Future<void> _updateProfile() async {
    final trimmedUserName = _userNameController.text.trim();
    final trimmedName = _nameController.text.trim();

    if (trimmedUserName.isEmpty || trimmedName.isEmpty) {
      AppSnackBar.warning(context, 'Username and Name cannot be empty.');
      return;
    }

    if (RegExp(r'\s').hasMatch(trimmedUserName)) {
      AppSnackBar.warning(context, 'Username cannot contain spaces.');
      return;
    }

    if (_usernameStatus == _UsernameStatus.taken) {
      AppSnackBar.error(
        context,
        'Username is already taken. Please choose another.',
      );
      return;
    }

    if (!Hive.isBoxOpen('userBox')) {
      AppSnackBar.error(context, 'User data not found.');
      return;
    }

    final user = Hive.box<UserModel>('userBox').get('currentUser');
    if (user == null) {
      AppSnackBar.error(context, 'User data not found.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      final saved = await ref
          .read(authControllerProvider)
          .saveUserDatatoFirebase(
            context,
            trimmedName,
            _selectedImage,
            userName: trimmedUserName,
            profilePicUrlOverride:
                _selectedImage == null ? _selectedImageUrl : null,
            navigateHomeOnComplete: false,
            removeProfilePic: _removePhotoRequested,
          );
      if (!mounted) return;
      if (saved) {
        setState(() {
          _initialName = trimmedName;
          _initialUserName = trimmedUserName;
          _selectedImage = null;
          _selectedImageUrl = null;
          _removePhotoRequested = false;
          _usernameStatus = _UsernameStatus.none;
        });
        AppSnackBar.success(context, 'Profile updated!');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Error updating profile: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Hive.isBoxOpen('userBox')) {
      return _buildScaffold(context, null);
    }
    return ValueListenableBuilder(
      valueListenable: Hive.box<UserModel>('userBox').listenable(),
      builder: (context, Box<UserModel> userBox, _) {
        return _buildScaffold(context, userBox.get('currentUser'));
      },
    );
  }

  Widget _buildScaffold(BuildContext context, UserModel? user) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161426),
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: const Icon(Icons.settings_rounded, color: Colors.white),
              tooltip: 'Settings',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ),
        ],
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
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeroCard(user),
                    const SizedBox(height: 22),
                    SettingsScreen.buildSectionTitle('IDENTITY DETAILS'),
                    const SizedBox(height: 10),
                    SettingsScreen.buildCard([
                      _buildInputRow(
                        icon: Icons.badge_rounded,
                        iconColor: const Color(0xFFFFD700),
                        label: 'Display Name',
                        hint: 'Enter your full name',
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                      ),
                      Divider(
                        height: 1,
                        indent: 62,
                        endIndent: 14,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                      _buildInputRow(
                        icon: Icons.alternate_email_rounded,
                        iconColor: tabColor,
                        label: 'Username',
                        hint: 'unique_username',
                        controller: _userNameController,
                        prefixText: '@',
                        textInputAction: TextInputAction.done,
                        trailing: _buildUsernameStatusIndicator(),
                      ),
                      Divider(
                        height: 1,
                        indent: 62,
                        endIndent: 14,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                      _buildEmailRow(user?.email),
                    ]),
                    const SizedBox(height: 20),
                    _buildSaveButton(),
                    const SizedBox(height: 24),
                    SettingsScreen.buildSectionTitle('ACCOUNT'),
                    const SizedBox(height: 10),
                    SettingsScreen.buildCard([
                      if ((user?.email?.trim() ?? '').isNotEmpty) ...[
                        SettingsScreen.buildRow(
                          icon: Icons.lock_reset_rounded,
                          iconColor: const Color(0xFF38BDF8),
                          title: 'Reset Password',
                          subtitle:
                              'Send a password reset link to ${user!.email!.trim()}',
                          onTap: () =>
                              _confirmPasswordReset(user.email!.trim()),
                        ),
                        Divider(
                          height: 1,
                          indent: 62,
                          endIndent: 14,
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ],
                      SettingsScreen.buildRow(
                        icon: Icons.logout_rounded,
                        iconColor: const Color(0xFFFF5252),
                        title: 'Sign Out',
                        subtitle: 'Log out from this device',
                        onTap: _confirmSignOut,
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(UserModel? user) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tabColor.withValues(alpha: 0.14),
            accentOrange.withValues(alpha: 0.07),
            const Color(0xFF161426),
          ],
        ),
        border: Border.all(
          color: tabColor.withValues(alpha: 0.28),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: tabColor.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _showAvatarOptions(user),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Hero(
                  tag: user?.uid ?? 'default_profile_tag',
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          tabColor,
                          accentOrange,
                          Color(0xFFFFD700),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: tabColor.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFF161426),
                        shape: BoxShape.circle,
                      ),
                      child: _selectedImage != null &&
                              _selectedImage!.existsSync()
                          ? ClipOval(
                              child: Image.file(
                                _selectedImage!,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                              ),
                            )
                          : UserAvatar(
                              url: _removePhotoRequested
                                  ? null
                                  : (_selectedImageUrl ?? user?.profilePic),
                              radius: 50,
                              backgroundColor: const Color(0xFF231F38),
                            ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [tabColor, accentOrange],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF161426),
                        width: 2.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ListenableBuilder(
            listenable: Listenable.merge([
              _nameController,
              _userNameController,
            ]),
            builder: (context, _) {
              final rawName = _nameController.text.trim();
              final displayName = rawName.isNotEmpty
                  ? rawName
                  : (user?.name?.trim().isNotEmpty == true
                        ? user!.name!.trim()
                        : 'Devotee');
              final rawHandle = _userNameController.text.trim();
              final handle = rawHandle.isNotEmpty
                  ? rawHandle
                  : (user?.userName?.trim().isNotEmpty == true
                        ? user!.userName!.trim()
                        : '');

              return Column(
                children: [
                  Text(
                    displayName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (handle.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _copyUsername(handle),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: tabColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: tabColor.withValues(alpha: 0.4),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '@$handle',
                              style: const TextStyle(
                                color: Color(0xFFFF80AB),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Icon(
                              Icons.copy_rounded,
                              size: 12,
                              color: const Color(0xFFFF80AB)
                                  .withValues(alpha: 0.85),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget? _buildUsernameStatusIndicator() {
    switch (_usernameStatus) {
      case _UsernameStatus.none:
        return null;
      case _UsernameStatus.checking:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 1.8, color: tabColor),
        );
      case _UsernameStatus.available:
        return _buildStatusBadge('Available', const Color(0xFF00E676));
      case _UsernameStatus.taken:
        return _buildStatusBadge('Taken', const Color(0xFFFF5252));
      case _UsernameStatus.invalidSpaces:
        return _buildStatusBadge('No spaces', const Color(0xFFFFB300));
    }
  }

  Widget _buildStatusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildInputRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String hint,
    required TextEditingController controller,
    String? prefixText,
    TextInputAction textInputAction = TextInputAction.next,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildIconBadge(icon: icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                TextField(
                  controller: controller,
                  textInputAction: textInputAction,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                    ),
                    prefixText: prefixText,
                    prefixStyle: TextStyle(
                      color: tabColor.withValues(alpha: 0.9),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _buildEmailRow(String? email) {
    final cleanEmail = email?.trim() ?? '';
    final hasEmail = cleanEmail.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _buildIconBadge(
            icon: Icons.mail_rounded,
            color: const Color(0xFF38BDF8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account Email',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasEmail ? cleanEmail : 'Not linked',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.lock_outline_rounded,
            size: 16,
            color: Colors.grey[600],
          ),
        ],
      ),
    );
  }

  Widget _buildIconBadge({required IconData icon, required Color color}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Icon(icon, size: 19, color: color),
    );
  }

  Widget _buildSaveButton() {
    return ListenableBuilder(
      listenable: Listenable.merge([_nameController, _userNameController]),
      builder: (context, _) {
        final hasChanges = _hasUnsavedChanges;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: _isLoading
                      ? [
                          tabColor.withValues(alpha: 0.5),
                          accentOrange.withValues(alpha: 0.5),
                        ]
                      : const [tabColor, accentOrange],
                ),
                boxShadow: _isLoading
                    ? null
                    : [
                        BoxShadow(
                          color:
                              tabColor.withValues(alpha: hasChanges ? 0.35 : 0.2),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _updateProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Update Profile',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            if (hasChanges) ...[
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  const Text(
                    'You have unsaved profile changes',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  InkWell(
                    onTap: _isLoading ? null : _discardUnsavedChanges,
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        'Discard',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AvatarFullScreenViewer extends StatelessWidget {
  final String heroTag;
  final File? imageFile;
  final String? imageUrl;

  const _AvatarFullScreenViewer({
    required this.heroTag,
    this.imageFile,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile Photo',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 3.5,
          child: Hero(
            tag: heroTag,
            child: imageFile != null
                ? Image.file(imageFile!, fit: BoxFit.contain)
                : CachedNetworkImage(
                    imageUrl: imageUrl!,
                    fit: BoxFit.contain,
                  ),
          ),
        ),
      ),
    );
  }
}

class CropImageScreen extends StatefulWidget {
  final File imageFile;

  const CropImageScreen({super.key, required this.imageFile});

  @override
  State<CropImageScreen> createState() => _CropImageScreenState();
}

class _CropImageScreenState extends State<CropImageScreen> {
  final GlobalKey<ExtendedImageEditorState> _editorKey =
      GlobalKey<ExtendedImageEditorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppSnackBar.info(
        context,
        'Tap and drag inside the crop box to move it',
        duration: const Duration(seconds: 4),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161426),
        elevation: 0,
        title: const Text(
          'Crop Profile Photo',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_rounded, color: tabColor),
            tooltip: 'Apply crop',
            onPressed: () async {
              final navigator = Navigator.of(context);
              final cropRect = _editorKey.currentState?.getCropRect();
              if (cropRect != null) {
                final croppedImage = await _cropImageToFile(
                  widget.imageFile,
                  cropRect,
                );
                if (!mounted) return;
                if (croppedImage != null) {
                  navigator.pop(croppedImage);
                }
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          ExtendedImage.file(
            widget.imageFile,
            fit: BoxFit.contain,
            mode: ExtendedImageMode.editor,
            extendedImageEditorKey: _editorKey,
            initEditorConfigHandler: (state) {
              return EditorConfig(
                maxScale: 1.5, // Reduced to minimize image zooming
                cropRectPadding: const EdgeInsets.all(30.0),
                cropAspectRatio: 1.0, // Square aspect ratio
                cornerColor: tabColor,
                cornerSize: const Size(40.0, 40.0), // Larger corners
                hitTestSize: 50.0, // Larger hit area for dragging
                lineColor: Colors.white.withValues(
                  alpha: 0.8,
                ), // Clearer crop box outline
                editorMaskColorHandler: (context, pointerDown) =>
                    Colors.black.withValues(alpha: pointerDown ? 0.6 : 0.4),
              );
            },
            initGestureConfigHandler: (state) {
              return GestureConfig(
                minScale: 1.0,
                maxScale: 1.5, // Limit zoom to reduce image panning
                speed: 1.0,
                inertialSpeed: 100.0,
                inPageView: false,
                cacheGesture:
                    false, // Disable gesture caching to prioritize crop box
              );
            },
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161426).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: tabColor.withValues(alpha: 0.35),
                        width: 0.8,
                      ),
                    ),
                    child: const Text(
                      'Tap and drag the crop box to position it',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<File?> _cropImageToFile(File imageFile, Rect cropRect) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final cropped = img.copyCrop(
        image,
        x: cropRect.left.toInt(),
        y: cropRect.top.toInt(),
        width: cropRect.width.toInt(),
        height: cropRect.height.toInt(),
      );

      final tempDir = await getTemporaryDirectory();
      final croppedFile = File(
        '${tempDir.path}/cropped_${imageFile.path.split('/').last}',
      );
      await croppedFile.writeAsBytes(img.encodeJpg(cropped));
      return croppedFile;
    } catch (e) {
      debugPrint('Crop processing error: $e');
      return null;
    }
  }
}
