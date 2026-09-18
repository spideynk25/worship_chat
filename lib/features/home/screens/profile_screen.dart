import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:extended_image/extended_image.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/models/user_model.dart';

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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final userBox = Hive.box<UserModel>('userBox');
    final user = userBox.get('currentUser');
    if (user != null) {
      _userNameController.text = user.userName ?? '';
      _nameController.text = user.name ?? '';
    }
  }

  @override
  void dispose() {
    _userNameController.dispose();
    _nameController.dispose();
    super.dispose();
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
      print('Crop error: $e');
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
      print('Resize error: $e');
      return null;
    }
  }

  Future<void> _pickImage() async {
    try {
      final pickedImage = await pickImageFromGallery(context);
      if (pickedImage != null) {
        final cropped = await _cropImage(pickedImage);
        if (cropped != null) {
          final resized = await _resizeImage(cropped);
          if (resized != null) {
            setState(() {
              _selectedImage = resized;
            });
          }
        }
      }
    } catch (e) {
      print('Image picking error: $e');
    }
  }

  Future<void> _updateProfile() async {
    if (_userNameController.text.isEmpty || _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Username and Name cannot be empty.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final userBox = Hive.box<UserModel>('userBox');
    final user = userBox.get('currentUser');

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User data not found.'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      ref
          .read(authControllerProvider)
          .saveUserDatatoFirebase(
            context,
            _nameController.text.trim(),
            _selectedImage,
            userName: _userNameController.text.trim(),
          );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating profile: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box<UserModel>('userBox').listenable(),
      builder: (context, Box<UserModel> userBox, _) {
        final user = userBox.get('currentUser');
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Profile', style: TextStyle(color: Colors.white)),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  appBarColor.withOpacity(0.9),
                  Colors.black.withOpacity(0.7),
                ],
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Hero(
                          tag: user?.uid ?? 'default_profile_tag',
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 80,
                              backgroundImage:
                                  _selectedImage != null &&
                                      _selectedImage!.existsSync()
                                  ? FileImage(_selectedImage!)
                                  : (user?.profilePic != null &&
                                            user!.profilePic!.isNotEmpty
                                        ? NetworkImage(user.profilePic!)
                                              as ImageProvider
                                        : null),
                              child:
                                  (user?.profilePic == null ||
                                          user!.profilePic!.isEmpty) &&
                                      _selectedImage == null
                                  ? const Icon(
                                      Icons.person,
                                      size: 80,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: tabColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildTextField(
                    'Username',
                    _userNameController,
                    Icons.person_outline,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField('Name', _nameController, Icons.badge),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    color: Colors.white.withOpacity(0.1),
                    child: ListTile(
                      leading: const Icon(Icons.email, color: Colors.white70),
                      title: Text(
                        user?.email ?? 'Loading...',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _updateProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tabColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            )
                          : const Text(
                              'Update Profile',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextFormField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white70),
            prefixIcon: Icon(icon, color: Colors.white70),
            border: InputBorder.none,
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
  _CropImageScreenState createState() => _CropImageScreenState();
}

class _CropImageScreenState extends State<CropImageScreen> {
  final GlobalKey<ExtendedImageEditorState> _editorKey =
      GlobalKey<ExtendedImageEditorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tap and drag inside the crop box to move it'),
          duration: Duration(seconds: 4),
          backgroundColor: Colors.black54,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: tabColor,
        title: const Text('Crop Image', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.white),
            onPressed: () async {
              final cropRect = _editorKey.currentState?.getCropRect();
              if (cropRect != null) {
                final croppedImage = await _cropImageToFile(
                  widget.imageFile,
                  cropRect,
                );
                if (croppedImage != null && mounted) {
                  Navigator.pop(context, croppedImage);
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
                lineColor: Colors.white.withOpacity(
                  0.8,
                ), // Clearer crop box outline
                editorMaskColorHandler: (context, pointerDown) =>
                    Colors.black.withOpacity(pointerDown ? 0.6 : 0.4),
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
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Tap and drag the crop box to position it',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
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
      print('Crop processing error: $e');
      return null;
    }
  }
}
