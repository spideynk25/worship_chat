import 'dart:io';
import 'dart:math' as math;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/utils/group_template_helper.dart';
import 'package:worship_chat/features/group/utils/queendom_emblem_helper.dart';
import 'package:worship_chat/features/group/widgets/select_contacts_group.dart';
import 'package:worship_chat/models/group.dart';

Uint8List? _cropSubGroupImageIsolate(Map<String, dynamic> params) {
  try {
    final Uint8List rawData = params['rawData'] as Uint8List;
    final double left = (params['left'] as num).toDouble();
    final double top = (params['top'] as num).toDouble();
    final double width = (params['width'] as num).toDouble();
    final double height = (params['height'] as num).toDouble();
    final double rotate = (params['rotate'] as num?)?.toDouble() ?? 0.0;
    final bool flipY = (params['flipY'] as bool?) ?? false;

    img.Image? image = img.decodeImage(rawData);
    if (image == null) return null;

    // Handle rotation: radians vs degrees
    double degrees;
    if (rotate.abs() <= 2 * math.pi) {
      degrees = rotate * 180 / math.pi;
    } else {
      degrees = rotate;
    }
    if (degrees % 360 != 0) {
      image = img.copyRotate(image, angle: degrees);
    }

    if (flipY) {
      image = img.flipHorizontal(image);
    }

    final int x = left.round().clamp(0, image.width - 1);
    final int y = top.round().clamp(0, image.height - 1);
    final int w = width.round().clamp(1, image.width - x);
    final int h = height.round().clamp(1, image.height - y);

    final img.Image cropped = img.copyCrop(
      image,
      x: x,
      y: y,
      width: w,
      height: h,
    );

    final List<int> jpg = img.encodeJpg(cropped, quality: 90);
    return Uint8List.fromList(jpg);
  } catch (e) {
    return null;
  }
}

class _SubGroupImageCropScreen extends StatefulWidget {
  final File file;
  final Function(File) onCropped;

  const _SubGroupImageCropScreen({required this.file, required this.onCropped});

  @override
  State<_SubGroupImageCropScreen> createState() =>
      _SubGroupImageCropScreenState();
}

class _SubGroupImageCropScreenState extends State<_SubGroupImageCropScreen> {
  final GlobalKey<ExtendedImageEditorState> editorKey = GlobalKey();
  bool _isCropping = false;

  Future<void> _cropImage() async {
    if (_isCropping) return;
    setState(() => _isCropping = true);

    try {
      final state = editorKey.currentState;
      if (state == null) {
        setState(() => _isCropping = false);
        return;
      }

      final Uint8List stateData = state.rawImageData;
      final Uint8List rawData = stateData.isNotEmpty
          ? stateData
          : await widget.file.readAsBytes();

      final Rect? cropRect = state.getCropRect();
      final EditActionDetails? action = state.editAction;

      if (cropRect == null || action == null) {
        setState(() => _isCropping = false);
        return;
      }

      final Uint8List? croppedData = await compute(_cropSubGroupImageIsolate, {
        'rawData': rawData,
        'left': cropRect.left,
        'top': cropRect.top,
        'width': cropRect.width,
        'height': cropRect.height,
        'rotate': action.rotateAngle,
        'flipY': action.flipY,
      });

      if (croppedData == null) {
        if (mounted) {
          AppSnackBar.error(context, 'Failed to crop image. Please try again.');
          setState(() => _isCropping = false);
        }
        return;
      }

      final tempDir = Directory.systemTemp;
      final target = File(
        '${tempDir.path}/cropped_wife_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await target.writeAsBytes(croppedData);

      widget.onCropped(target);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Error cropping image: $e');
        setState(() => _isCropping = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crop Wife Profile Picture'),
        actions: [
          _isCropping
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              : IconButton(icon: const Icon(Icons.done), onPressed: _cropImage),
        ],
      ),
      body: Center(
        child: ExtendedImage.file(
          widget.file,
          fit: BoxFit.contain,
          mode: ExtendedImageMode.editor,
          cacheRawData: true,
          extendedImageEditorKey: editorKey,
          initEditorConfigHandler: (state) {
            return EditorConfig(
              maxScale: 8.0,
              cropRectPadding: const EdgeInsets.all(20),
              hitTestSize: 20,
              cornerColor: tabColor,
              lineColor: Colors.white,
              lineHeight: 2,
              cornerSize: const Size(30, 3),
              cropAspectRatio: 1,
            );
          },
        ),
      ),
    );
  }
}

class CreateSubGroupScreen extends ConsumerStatefulWidget {
  final GroupModel parentGroup;
  final String initialSubGroupType;

  const CreateSubGroupScreen({
    super.key,
    required this.parentGroup,
    this.initialSubGroupType = 'wife',
  });

  @override
  ConsumerState<CreateSubGroupScreen> createState() =>
      _CreateSubGroupScreenState();
}

class _CreateSubGroupScreenState extends ConsumerState<CreateSubGroupScreen> {
  final TextEditingController nameController = TextEditingController();
  File? image;
  bool isCreating = false;
  late String _selectedSubGroupType;

  bool get _isFuckToy => _selectedSubGroupType == 'fuckToy';
  String get _categoryTitle => _isFuckToy ? 'Fuck Toy' : 'Wife';

  Color get _accentColor {
    if (widget.parentGroup.queendom == 'Queen Pooja') {
      return const Color(0xFFFFD700);
    } else if (widget.parentGroup.queendom == 'Queen Rashmika') {
      return const Color(0xFFFF4081);
    }
    return tabColor;
  }

  Color get _categoryColor => _isFuckToy ? Colors.purpleAccent : _accentColor;
  Color get categoryColor => _categoryColor;

  @override
  void initState() {
    super.initState();
    _selectedSubGroupType = widget.initialSubGroupType;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(selectedGroupContacts.notifier).state = [];
    });
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  void selectImage() async {
    final picked = await pickImageFromGallery(context);
    if (picked == null) return;

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _SubGroupImageCropScreen(
          file: picked,
          onCropped: (croppedFile) {
            setState(() {
              image = croppedFile;
            });
          },
        ),
      ),
    );
  }

  void _createSubGroup() async {
    final enteredName = nameController.text.trim();

    if (enteredName.isEmpty) {
      AppSnackBar.warning(context, 'Please enter the $_categoryTitle\'s name');
      return;
    }

    if (image == null) {
      AppSnackBar.warning(
        context,
        'Please select a profile picture for the $_categoryTitle',
      );
      return;
    }

    setState(() => isCreating = true);

    try {
      final selectedContacts = ref.read(selectedGroupContacts);
      final formattedMemberName = GroupTemplateHelper.toTitleCase(enteredName);
      final parentName = widget.parentGroup.nameWithPosition;
      final type = widget.parentGroup.queendom == 'Queen Pooja'
          ? 'queenPooja'
          : widget.parentGroup.queendom == 'Queen Rashmika'
          ? 'queenRashmika'
          : 'others';

      ref
          .read(groupControllerProvider)
          .createGroup(
            context,
            formattedMemberName,
            '🙇‍♀️🙇‍♀️ Hail $_categoryTitle $formattedMemberName of $parentName 🙇‍♀️🙇‍♀️',
            widget.parentGroup.queendom ?? 'None',
            widget.parentGroup.family ?? 'None',
            '$_categoryTitle of $parentName',
            image!,
            selectedContacts,
            type,
            livingPlace: widget.parentGroup.effectiveLivingPlace,
            priority: null,
            parentGroupId: widget.parentGroup.groupId,
            parentGroupName: parentName,
            isSubGroup: true,
            subGroupType: _selectedSubGroupType,
          );

      ref.read(selectedGroupContacts.notifier).state = [];

      if (mounted) {
        AppSnackBar.success(
          context,
          '$_categoryTitle sub-group created under $parentName!',
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Error creating sub-group: $e');
      }
    } finally {
      if (mounted) {
        setState(() => isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final parent = widget.parentGroup;
    final parentTitle = parent.nameWithPosition;
    final accent = _accentColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          'Add $_categoryTitle Sub-Group',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: appBarColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Parent Deity Header Card ──────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent.withValues(alpha: 0.2), Colors.grey[900]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundImage: parent.groupPic.isNotEmpty
                            ? NetworkImage(parent.groupPic)
                            : null,
                        backgroundColor: Colors.grey[800],
                        child: parent.groupPic.isEmpty
                            ? const Icon(Icons.group, color: Colors.white)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.auto_awesome, color: accent, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                'PARENT DEITY',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: accent,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            parentTitle,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          QueendomEmblemHelper.buildRichTitle(
                            title: '🏰 ${parent.effectiveLivingPlace}',
                            family: parent.family,
                            fallbackFamily: 'Main',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            emblemSize: 14,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Sub-Group Category Selector ───────────────────────────
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedSubGroupType = 'wife';
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: !_isFuckToy
                                ? accent.withValues(alpha: 0.25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: !_isFuckToy ? accent : Colors.transparent,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.favorite_rounded,
                                size: 16,
                                color: !_isFuckToy ? accent : Colors.white54,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Wife',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: !_isFuckToy
                                      ? Colors.white
                                      : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedSubGroupType = 'fuckToy';
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _isFuckToy
                                ? Colors.purpleAccent.withValues(alpha: 0.25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _isFuckToy
                                  ? Colors.purpleAccent
                                  : Colors.transparent,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.local_fire_department_rounded,
                                size: 16,
                                color: _isFuckToy
                                    ? Colors.purpleAccent
                                    : Colors.white54,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Fuck Toy',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: _isFuckToy
                                      ? Colors.white
                                      : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Profile Image Picker ──────────────────────────────────
              Center(
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: categoryColor.withValues(alpha: 0.8),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: categoryColor.withValues(alpha: 0.25),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 54,
                        backgroundImage: image != null
                            ? FileImage(image!)
                            : null,
                        backgroundColor: Colors.grey[850],
                        child: image == null
                            ? Icon(
                                _isFuckToy
                                    ? Icons.local_fire_department_rounded
                                    : Icons.person_add_alt_1_rounded,
                                size: 48,
                                color: categoryColor,
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: selectImage,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: categoryColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: backgroundColor,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 18,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Tap camera icon to select $_categoryTitle picture',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Name Field ────────────────────────────────────────────
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '$_categoryTitle Name',
                  hintText: 'Enter name',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  labelStyle: TextStyle(color: categoryColor),
                  prefixIcon: Icon(
                    _isFuckToy
                        ? Icons.local_fire_department_rounded
                        : Icons.favorite_outline,
                    color: categoryColor,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[800]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: categoryColor, width: 1.5),
                  ),
                  filled: true,
                  fillColor: Colors.grey[900],
                ),
              ),

              // ── Live Title Preview ────────────────────────────────────
              if (nameController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: categoryColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: categoryColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Display name: ${GroupTemplateHelper.getNameWithPosition(name: nameController.text.trim(), parentGroupName: parentTitle, isSubGroup: true, subGroupType: _selectedSubGroupType)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: categoryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // ── Living Place Notice Banner ────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12, width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.home_outlined,
                      size: 18,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Shared Sanctum & Living Place',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Lives in $parentTitle\'s sanctum (${parent.effectiveLivingPlace}). Wish and living place are inherited automatically.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Select Contacts for the Sub-Group ─────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Members',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '${parent.membersUid.length} deity members',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: categoryColor.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SelectContactsGroup(
                initialMemberUids: parent.membersUid,
                parentGroupName: parentTitle,
                accentColor: categoryColor,
                height: 380,
              ),

              const SizedBox(height: 24),

              // ── Create Button ─────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isCreating ? null : _createSubGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: categoryColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 3,
                  ),
                  child: isCreating
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          'Create $_categoryTitle Sub-Group',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
