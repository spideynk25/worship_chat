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
import 'package:worship_chat/features/group/utils/group_template_helper.dart';
import 'package:worship_chat/features/group/utils/queendom_emblem_helper.dart';
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
    'Velisse',
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

  final TextEditingController nameController = TextEditingController();
  final TextEditingController livingPlaceController = TextEditingController();
  final TextEditingController wishController = TextEditingController();
  final TextEditingController priorityController = TextEditingController();

  List<int> _takenPriorities = [];
  bool _isLoadingPriorities = false;

  File? image;

  bool get _requiresPriority =>
      selectedPosition != 'None' &&
      !GroupTemplateHelper.categoryHasOtherFamilies(selectedPosition);

  bool get _hasOtherFamilies =>
      GroupTemplateHelper.categoryHasOtherFamilies(selectedPosition);

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

  void _onCategoryOrQueendomChanged() {
    if (_requiresPriority) {
      selectedFamily = 'None';
      _fetchTakenPriorities();
    } else {
      _takenPriorities = [];
    }
    _autoFillTemplates();
  }

  Future<void> _fetchTakenPriorities() async {
    if (selectedQueendom == 'None' || selectedPosition == 'None') {
      if (mounted) setState(() => _takenPriorities = []);
      return;
    }
    if (mounted) setState(() => _isLoadingPriorities = true);
    final taken = await ref.read(groupControllerProvider).getTakenPriorities(
          queendom: selectedQueendom,
          position: selectedPosition,
        );
    if (mounted) {
      setState(() {
        _takenPriorities = taken;
        _isLoadingPriorities = false;
        // Suggest the next lowest unused positive integer
        if (priorityController.text.trim().isEmpty) {
          int next = 1;
          while (_takenPriorities.contains(next)) {
            next++;
          }
          priorityController.text = next.toString();
        }
      });
    }
  }

  void _autoFillTemplates() {
    final result = GroupTemplateHelper.generateTemplate(
      position: selectedPosition,
      name: nameController.text.trim(),
      family: selectedFamily,
    );

    if (result.livingPlace.isNotEmpty) {
      livingPlaceController.text = result.livingPlace;
    }
    if (result.wish.isNotEmpty) {
      wishController.text = result.wish;
    }
    setState(() {});
  }

  bool _isEnteredPriorityTaken() {
    final val = int.tryParse(priorityController.text.trim());
    if (val == null) return false;
    return _takenPriorities.contains(val);
  }

  void createGroup() async {
    final name = nameController.text.trim();
    final livingPlace = livingPlaceController.text.trim();
    final wish = wishController.text.trim();

    if (name.isEmpty) {
      AppSnackBar.warning(context, 'Please enter deity or group member name');
      return;
    }

    if (image == null) {
      AppSnackBar.warning(context, 'Please select a group profile picture');
      return;
    }

    int? priority;
    if (_requiresPriority) {
      final pVal = int.tryParse(priorityController.text.trim());
      if (pVal == null || pVal <= 0) {
        AppSnackBar.warning(
          context,
          'Please enter a valid priority number for $selectedPosition (1, 2, ...)',
        );
        return;
      }

      // Re-verify uniqueness with latest Firestore data
      final taken = await ref.read(groupControllerProvider).getTakenPriorities(
            queendom: selectedQueendom,
            position: selectedPosition,
          );
      if (taken.contains(pVal)) {
        AppSnackBar.warning(
          context,
          'Priority $pVal is already taken for $selectedPosition in $selectedQueendom. Taken: ${taken.join(', ')}',
        );
        return;
      }
      priority = pVal;
    }

    ref.read(groupControllerProvider).createGroup(
          context,
          name,
          wish.isEmpty ? null : wish,
          selectedQueendom,
          selectedFamily,
          selectedPosition,
          image!,
          ref.read(selectedGroupContacts),
          selectedQueendom == 'Queen Pooja'
              ? 'queenPooja'
              : selectedQueendom == 'Queen Rashmika'
                  ? 'queenRashmika'
                  : 'others',
          livingPlace: livingPlace.isNotEmpty ? livingPlace : null,
          priority: priority,
        );

    ref.read(selectedGroupContacts.notifier).state = [];
    Navigator.pop(context);
  }

  @override
  void dispose() {
    nameController.dispose();
    livingPlaceController.dispose();
    wishController.dispose();
    priorityController.dispose();
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
            const SizedBox(height: 12),

            // 1. Deity / Character Name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                controller: nameController,
                onChanged: (_) => _autoFillTemplates(),
                decoration: const InputDecoration(
                  labelText: 'Deity / Member Name',
                  hintText: 'e.g. Pooja, Rashmika, Anu',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
            ),

            // 2. Queendom dropdown
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: DropdownButtonFormField<String>(
                value: selectedQueendom,
                decoration: const InputDecoration(
                  labelText: 'Queendom',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.castle_outlined),
                ),
                items: queendom
                    .map(
                      (type) =>
                          DropdownMenuItem(value: type, child: Text(type)),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    selectedQueendom = value ?? "None";
                    _onCategoryOrQueendomChanged();
                  });
                },
              ),
            ),

            // 3. Position dropdown
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: DropdownButtonFormField<String>(
                value: selectedPosition,
                decoration: const InputDecoration(
                  labelText: 'Position / Category',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.star_outline),
                ),
                items: positions
                    .map(
                      (pos) => DropdownMenuItem(
                        value: pos,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (pos != 'None') ...[
                              QueendomEmblemWidget(position: pos, size: 18),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                pos,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: selectedQueendom == 'None'
                    ? null
                    : (value) {
                        setState(() {
                          selectedPosition = value ?? "None";
                          _onCategoryOrQueendomChanged();
                        });
                      },
              ),
            ),

            // 4. Family dropdown (only visible when position has other families)
            if (_hasOtherFamilies)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: DropdownButtonFormField<String>(
                  value: selectedFamily,
                  decoration: const InputDecoration(
                    labelText: 'Family',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.diversity_3_outlined),
                  ),
                  items: families
                      .map(
                        (fam) => DropdownMenuItem(
                          value: fam,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (fam != 'None') ...[
                                QueendomFamilyEmblemWidget(
                                  family: fam,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                              ],
                              Text(fam),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedFamily = value ?? "None";
                      _autoFillTemplates();
                    });
                  },
                ),
              ),


            // 5. Priority field (for categories that don't have other families)
            if (_requiresPriority)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: priorityController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Priority (Ordering in Category)',
                    hintText: 'e.g. 1, 2, 3...',
                    border: const OutlineInputBorder(),
                    prefixIcon:
                        const Icon(Icons.format_list_numbered_rounded),
                    helperText: _isLoadingPriorities
                        ? 'Checking taken priorities...'
                        : (_takenPriorities.isNotEmpty
                            ? 'Taken priorities in this category: [${_takenPriorities.join(', ')}]'
                            : 'No existing groups in this category yet. (Suggested: 1)'),
                    errorText: _isEnteredPriorityTaken()
                        ? 'Priority is already taken in this category!'
                        : null,
                  ),
                ),
              ),

            // 6. Living Place field (auto-populated by template)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                controller: livingPlaceController,
                decoration: InputDecoration(
                  labelText: 'Living Place',
                  hintText: 'Auto-generated or custom living place',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.temple_buddhist_outlined),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Regenerate from template',
                    onPressed: _autoFillTemplates,
                  ),
                ),
              ),
            ),

            // 7. Wish field (auto-populated by template)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                controller: wishController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Wish',
                  hintText: 'Auto-generated or custom wish',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.favorite_outline),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Regenerate from template',
                    onPressed: _autoFillTemplates,
                  ),
                ),
                enabled: selectedQueendom != 'None',
              ),
            ),

            const SizedBox(height: 10),
            Container(
              alignment: Alignment.topLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: const Text(
                'Select Contacts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),

            /// Fixed: Give SelectContactsGroup a proper height
            SizedBox(
              height: height * 0.45,
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
