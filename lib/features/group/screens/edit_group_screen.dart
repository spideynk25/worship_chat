import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:extended_image/extended_image.dart';
import 'package:image/image.dart' as img;
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/models/group.dart';

class EditGroupScreen extends ConsumerStatefulWidget {
  static const String routeName = '/edit-group';
  final GroupModel group;
  final String type;
  const EditGroupScreen({super.key, required this.group, required this.type});

  @override
  ConsumerState<EditGroupScreen> createState() => _EditGroupScreenState();
}

class _EditGroupScreenState extends ConsumerState<EditGroupScreen> {
  // Dropdown values
  late String selectedQueendom;
  late String selectedFamily;
  late String selectedPosition;

  final List<String> queendom = ['None', 'Queen Rashmika', 'Queen Pooja'];
  final List<String> families = [
    'None',
    'Aura',
    'Core',
    'Main',
    'Eternal',
    'Divine',
    'Wicked',
    'Lustra',
    'Rumia',
    'Erotica',
    'Elegant',
    'Elora',
    'Zyra'
  ];
  final List<String> positions = [
    'None',
    'Aura Elixiria',
    'Core Supreme Goddess',
    'Supreme Goddess',
    'Golden Blossom Goddess',
    'Goddess',
    'Demi Goddess',
    'Dark Angel',
    'Queen',
    'Elfwitch',
    'Enchantress',
    'First Born Princess',
    'Second Born Princess',
    'Third Born Princess',
  ];

  late TextEditingController groupNameController;
  late TextEditingController wishController;

  File? image;
  bool imageChanged = false;

  @override
  void initState() {
    super.initState();
    // Initialize with existing group data
    groupNameController = TextEditingController(text: widget.group.name);
    wishController = TextEditingController(text: widget.group.wish ?? '');
    selectedQueendom = widget.group.queendom ?? 'None';
    selectedFamily = widget.group.family ?? 'None';
    selectedPosition = widget.group.position ?? 'None';
  }

  /// Pick image then crop it before setting
  void selectImage() async {
    final picked = await pickImageFromGallery(context);
    if (picked == null) return;

    // open crop screen
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _ImageCropScreen(
          file: picked,
          onCropped: (croppedFile) {
            setState(() {
              image = croppedFile;
              imageChanged = true;
            });
          },
        ),
      ),
    );
  }

  void updateGroup() async {
    if (groupNameController.text.trim().isNotEmpty) {
      if (selectedQueendom != 'None' && wishController.text.trim().isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please enter a wish')));
        return;
      }

      await ref
          .read(groupControllerProvider)
          .updateGroup(
            context,
            widget.group.groupId,
            groupNameController.text.trim(),
            wishController.text.trim().isEmpty
                ? null
                : wishController.text.trim(),
            selectedQueendom,
            selectedFamily,
            selectedPosition,
            imageChanged ? image : null,
            widget.type
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group updated successfully')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
    }
  }

  @override
  void dispose() {
    groupNameController.dispose();
    wishController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Group"),
        actions: [
          TextButton(
            onPressed: updateGroup,
            child: const Text(
              'Save',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Center(
              child: Stack(
                children: [
                  image == null
                      ? CircleAvatar(
                          backgroundColor: greyColor,
                          radius: 64,
                          backgroundImage: widget.group.groupPic.isNotEmpty
                              ? NetworkImage(widget.group.groupPic)
                              : null,
                          child: widget.group.groupPic.isEmpty
                              ? const Icon(
                                  Icons.group,
                                  color: blackColor,
                                  size: 70,
                                )
                              : null,
                        )
                      : CircleAvatar(
                          radius: 64,
                          backgroundImage: FileImage(image!),
                        ),
                  Positioned(
                    bottom: -10,
                    left: 80,
                    child: IconButton(
                      onPressed: selectImage,
                      icon: const Icon(Icons.camera_alt),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: groupNameController,
              decoration: const InputDecoration(
                labelText: 'Group name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.group),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedQueendom,
              decoration: const InputDecoration(
                labelText: 'Queendom',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.castle),
              ),
              items: queendom
                  .map(
                    (type) => DropdownMenuItem(value: type, child: Text(type)),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  selectedQueendom = value ?? "None";
                  if (selectedQueendom == 'None') {
                    selectedFamily = 'None';
                    selectedPosition = 'None';
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedFamily,
              decoration: const InputDecoration(
                labelText: 'Family',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.people),
              ),
              items: families
                  .map((fam) => DropdownMenuItem(value: fam, child: Text(fam)))
                  .toList(),
              onChanged: selectedQueendom == 'None'
                  ? null
                  : (value) {
                      setState(() {
                        selectedFamily = value ?? "None";
                      });
                    },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedPosition,
              decoration: const InputDecoration(
                labelText: 'Position',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.star),
              ),
              items: positions
                  .map((pos) => DropdownMenuItem(value: pos, child: Text(pos)))
                  .toList(),
              onChanged: selectedQueendom == 'None'
                  ? null
                  : (value) {
                      setState(() {
                        selectedPosition = value ?? "None";
                      });
                    },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: wishController,
              decoration: const InputDecoration(
                labelText: 'Wish',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.favorite),
              ),
              maxLines: 3,
              enabled: selectedQueendom != 'None',
            ),
          ],
        ),
      ),
    );
  }
}

// Reuse the same crop helpers from create_group_screen.dart
Uint8List? _cropImageIsolate(Map<String, dynamic> params) {
  try {
    final Uint8List rawData = params['rawData'] as Uint8List;
    final double left = (params['left'] as num).toDouble();
    final double top = (params['top'] as num).toDouble();
    final double width = (params['width'] as num).toDouble();
    final double height = (params['height'] as num).toDouble();
    final double rotate = (params['rotate'] as num?)?.toDouble() ?? 0.0;
    final bool flipY = params['flipY'] as bool? ?? false;

    img.Image? image = img.decodeImage(rawData);
    if (image == null) return null;

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

class _ImageCropScreen extends StatefulWidget {
  final File file;
  final Function(File) onCropped;

  const _ImageCropScreen({
    Key? key,
    required this.file,
    required this.onCropped,
  }) : super(key: key);

  @override
  State<_ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<_ImageCropScreen> {
  final GlobalKey<ExtendedImageEditorState> editorKey = GlobalKey();

  Future<void> _cropImage() async {
    final state = editorKey.currentState;
    if (state == null) return;

    final Uint8List? rawData = state.rawImageData;
    final Rect? cropRect = state.getCropRect();
    final EditActionDetails? action = state.editAction;

    if (rawData == null || cropRect == null || action == null) {
      return;
    }

    final Uint8List? croppedData = await compute(_cropImageIsolate, {
      'rawData': rawData,
      'left': cropRect.left,
      'top': cropRect.top,
      'width': cropRect.width,
      'height': cropRect.height,
      'rotate': action.rotateAngle,
      'flipY': action.flipY,
    });

    if (croppedData == null) return;

    final tempDir = Directory.systemTemp;
    final target = File(
      '${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await target.writeAsBytes(croppedData);

    widget.onCropped(target);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crop Image'),
        actions: [
          IconButton(icon: const Icon(Icons.done), onPressed: _cropImage),
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
              cornerColor: Colors.blueAccent,
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
