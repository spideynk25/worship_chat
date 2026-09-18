import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:extended_image/extended_image.dart';
import 'package:image/image.dart' as img;

import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/widgets/select_contacts_group.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  static const String routeName = '/create-group';
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  // Dropdown values
  String selectedQueendom = 'None';
  String selectedFamily = 'None';
  String selectedPosition = 'None';

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
    'Zyra',
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

  final TextEditingController groupNameController = TextEditingController();
  final TextEditingController wishController = TextEditingController();

  File? image;

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
            });
          },
        ),
      ),
    );
  }

  void createGroup() {
    if (groupNameController.text.trim().isNotEmpty && image != null) {
      ref
          .read(groupControllerProvider)
          .createGroup(
            context,
            groupNameController.text.trim(),
            wishController.text.trim().isEmpty
                ? null
                : wishController.text.trim(),
            selectedQueendom,
            selectedFamily,
            selectedPosition,
            image!,
            ref.read(selectedGroupContacts),
            "others",
          );
      ref.read(selectedGroupContacts.state).update((state) => []);
      Navigator.pop(context);
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
    final height = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: AppBar(title: const Text("Create Group")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Center(
              child: Stack(
                children: [
                  image == null
                      ? const CircleAvatar(
                          backgroundColor: greyColor,
                          radius: 64,
                          child: Icon(
                            Icons.person,
                            color: blackColor,
                            size: 70,
                          ),
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
                      icon: const Icon(Icons.add_a_photo),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: groupNameController,
                decoration: const InputDecoration(
                  hintText: 'Enter group name',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            // Dropdowns for Queendom Type, Family, and Position
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: DropdownButtonFormField<String>(
                value: selectedQueendom,
                decoration: const InputDecoration(labelText: 'Queendom'),
                items: queendom
                    .map(
                      (type) =>
                          DropdownMenuItem(value: type, child: Text(type)),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    selectedQueendom = value ?? "None";
                    selectedFamily = 'None';
                    selectedPosition = 'None';
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: DropdownButtonFormField<String>(
                value: selectedFamily,
                decoration: const InputDecoration(labelText: 'Family'),
                items: families
                    .map(
                      (fam) => DropdownMenuItem(value: fam, child: Text(fam)),
                    )
                    .toList(),
                onChanged: selectedQueendom == 'None'
                    ? null
                    : (value) {
                        setState(() {
                          selectedFamily = value ?? "None";
                        });
                      },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: DropdownButtonFormField<String>(
                value: selectedPosition,
                decoration: const InputDecoration(labelText: 'Position'),
                items: positions
                    .map(
                      (pos) => DropdownMenuItem(value: pos, child: Text(pos)),
                    )
                    .toList(),
                onChanged: selectedQueendom == 'None'
                    ? null
                    : (value) {
                        setState(() {
                          selectedPosition = value ?? "None";
                        });
                      },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: wishController,
                decoration: const InputDecoration(
                  hintText: 'Wish',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                enabled: selectedQueendom != 'None',
              ),
            ),
            Container(
              alignment: Alignment.topLeft,
              padding: const EdgeInsets.all(8),
              child: const Text(
                'Select Contact',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),

            /// ✅ Fixed: Give SelectContactsGroup a proper height
            SizedBox(
              height: height * 0.5, // half screen height for contacts
              child: const SelectContactsGroup(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: createGroup,
        backgroundColor: tabColor,
        child: const Icon(Icons.done, color: Colors.white),
      ),
    );
  }
}

//
// Crop helpers & crop screen
//

/// Top-level isolate function for cropping (used by compute).
/// Receives a Map with keys:
///  - rawData: Uint8List (image bytes)
///  - left, top, width, height: doubles for crop rect
///  - rotate: double (rotate angle; if small assume radians, otherwise degrees)
///  - flipY: bool
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

    // Rotate: handle radians vs degrees heuristic
    double degrees;
    if (rotate.abs() <= 2 * math.pi) {
      degrees = rotate * 180 / math.pi;
    } else {
      degrees = rotate;
    }
    // apply rotation if needed
    if (degrees % 360 != 0) {
      image = img.copyRotate(image, angle: degrees);
    }

    // flip horizontally if required
    if (flipY) {
      image = img.flipHorizontal(image);
    }

    // clamp crop rect to image bounds
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
    // In isolate — return null on error
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
      // nothing to crop
      return;
    }

    // Use compute to do heavy work in an isolate
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
          cacheRawData: true, // <--- IMPORTANT: we need raw bytes
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
              // 1:1 for avatar
              // circular crop box
            );
          },
        ),
      ),
    );
  }
}
