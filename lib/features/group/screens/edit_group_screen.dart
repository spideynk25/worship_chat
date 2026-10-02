import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:extended_image/extended_image.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/dashboard/controller/event_controller.dart';
import 'package:worship_chat/features/dashboard/repositories/event_repository.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/models/event.dart';
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

  // Birthday connection state
  late TextEditingController birthdayTitleController;
  DateTime? birthdayDate;
  bool isRecurringBirthday = true;
  Event? originalConnectedEvent;
  Event? selectedBirthdayEvent;
  bool isNewBirthday = false;
  bool isBirthdayDisconnected = false;
  bool isLoadingBirthday = true;

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

    birthdayTitleController = TextEditingController();
    _loadConnectedBirthday();
  }

  Future<void> _loadConnectedBirthday() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('events')
          .where('connectedGroupId', isEqualTo: widget.group.groupId)
          .limit(1)
          .get();

      Event? foundEvent;
      if (query.docs.isNotEmpty) {
        foundEvent = Event.fromFirestore(query.docs.first);
      }

      if (mounted) {
        setState(() {
          originalConnectedEvent = foundEvent;
          selectedBirthdayEvent = foundEvent;
          if (foundEvent != null) {
            birthdayTitleController.text = foundEvent.title;
            birthdayDate = foundEvent.date;
            isRecurringBirthday = foundEvent.isRecurring;
          } else {
            birthdayTitleController.text = selectedQueendom == 'Queen Pooja'
                ? "Queen Pooja's Birthday"
                : selectedQueendom == 'Queen Rashmika'
                    ? "Queen Rashmika's Birthday"
                    : "${widget.group.name} Birthday";
          }
          isLoadingBirthday = false;
        });
      }
    } catch (e) {
      log('Error loading connected birthday: $e');
      if (mounted) {
        setState(() => isLoadingBirthday = false);
      }
    }
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
        AppSnackBar.warning(context, 'Please enter a wish');
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
            widget.type,
          );

      // Persist Birthday / Event changes
      try {
        if (isBirthdayDisconnected) {
          if (originalConnectedEvent != null) {
            final cleared = originalConnectedEvent!.copyWith(
              clearConnectedGroup: true,
            );
            await ref.read(eventRepositoryProvider).updateEvent(cleared);
            log('✅ Birthday disconnected from group ${widget.group.groupId}');
          }
        } else if (selectedBirthdayEvent != null) {
          final cleanTitle = birthdayTitleController.text.trim().isNotEmpty
              ? birthdayTitleController.text.trim()
              : selectedBirthdayEvent!.title;
          final cleanDate = birthdayDate ?? selectedBirthdayEvent!.date;

          final queendomVal = selectedQueendom != 'None' ? selectedQueendom : null;

          if (selectedBirthdayEvent!.id.isNotEmpty) {
            // Existing event updated/connected
            final updated = selectedBirthdayEvent!.copyWith(
              title: cleanTitle,
              date: cleanDate,
              isRecurring: isRecurringBirthday,
              connectedGroupId: widget.group.groupId,
              connectedGroupName: groupNameController.text.trim(),
              connectedGroupPic: widget.group.groupPic,
              connectedQueendom: queendomVal,
            );
            await ref.read(eventRepositoryProvider).updateEvent(updated);

            // If user swapped from another event, unlink the old one
            if (originalConnectedEvent != null &&
                originalConnectedEvent!.id != selectedBirthdayEvent!.id) {
              final cleared = originalConnectedEvent!.copyWith(
                clearConnectedGroup: true,
              );
              await ref.read(eventRepositoryProvider).updateEvent(cleared);
            }
            log('✅ Connected birthday updated: $cleanTitle');
          } else {
            // Create a brand new event connected to this group
            await ref.read(eventControllerProvider.notifier).createEvent(
                  title: cleanTitle,
                  description:
                      'Celebration for ${groupNameController.text.trim()}',
                  date: cleanDate,
                  time: const TimeOfDay(hour: 0, minute: 0),
                  isRecurring: isRecurringBirthday,
                  connectedGroupId: widget.group.groupId,
                  connectedGroupName: groupNameController.text.trim(),
                  connectedGroupPic: widget.group.groupPic,
                  connectedQueendom: queendomVal,
                );
            log('✅ New connected birthday created: $cleanTitle');
          }
        }
      } catch (e) {
        log('❌ Error updating connected birthday: $e');
      }

      if (mounted) {
        Navigator.pop(context);
        AppSnackBar.success(context, 'Group updated successfully');
      }
    } else {
      AppSnackBar.warning(context, 'Please enter a group name');
    }
  }

  @override
  void dispose() {
    groupNameController.dispose();
    wishController.dispose();
    birthdayTitleController.dispose();
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
            if (selectedQueendom != 'None') ...[
              const SizedBox(height: 20),
              _buildBirthdaySection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBirthdaySection() {
    final isPooja = selectedQueendom == 'Queen Pooja';
    final accentColor =
        isPooja ? const Color(0xFFFFD700) : const Color(0xFFFF4081);

    if (isLoadingBirthday) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text(
              'Checking connected birthday...',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final hasActiveBirthday =
        selectedBirthdayEvent != null && !isBirthdayDisconnected;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasActiveBirthday
            ? accentColor.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasActiveBirthday
              ? accentColor.withValues(alpha: 0.45)
              : Colors.white12,
          width: hasActiveBirthday ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  hasActiveBirthday ? Icons.cake_rounded : Icons.cake_outlined,
                  color: accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Royal Birthday / Celebration',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                    Text(
                      hasActiveBirthday
                          ? 'Connected to $selectedQueendom'
                          : 'No celebration event linked to this group',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasActiveBirthday)
                IconButton(
                  icon: const Icon(Icons.link_off_rounded,
                      color: Colors.redAccent, size: 20),
                  tooltip: 'Disconnect Birthday',
                  onPressed: () {
                    setState(() {
                      isBirthdayDisconnected = true;
                    });
                    AppSnackBar.info(
                      context,
                      'Birthday disconnected. Tap Save to apply.',
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (hasActiveBirthday) ...[
            // Editable Title
            TextField(
              controller: birthdayTitleController,
              decoration: InputDecoration(
                labelText: 'Birthday Title',
                hintText: 'e.g. Queen Pooja Birthday',
                border: const OutlineInputBorder(),
                prefixIcon: Icon(Icons.celebration, color: accentColor),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),

            // Date Picker Tile
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: birthdayDate ?? DateTime.now(),
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2100),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: ColorScheme.dark(
                          primary: accentColor,
                          surface: const Color(0xFF1E1830),
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (picked != null) {
                  setState(() {
                    birthdayDate = picked;
                  });
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                  color: Colors.black26,
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_month_rounded,
                        color: accentColor, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Birthday Date',
                            style:
                                TextStyle(fontSize: 11, color: Colors.white54),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            birthdayDate != null
                                ? DateFormat('EEEE, d MMMM yyyy')
                                    .format(birthdayDate!)
                                : 'Select date',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Change',
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Recurring Switch
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Annual Celebration (Recurring yearly)',
                style: TextStyle(fontSize: 13, color: Colors.white),
              ),
              subtitle: const Text(
                'Triggers annual birthday wishes and notification banners',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              value: isRecurringBirthday,
              activeColor: accentColor,
              onChanged: (val) {
                setState(() {
                  isRecurringBirthday = val;
                });
              },
            ),
            const SizedBox(height: 10),

            // Secondary switch/swap button
            Center(
              child: TextButton.icon(
                icon: Icon(Icons.swap_horiz_rounded,
                    size: 16, color: accentColor),
                label: Text(
                  'Switch to Different Birthday Event',
                  style: TextStyle(color: accentColor, fontSize: 12),
                ),
                onPressed: () => _showExistingBirthdayPicker(context),
              ),
            ),
          ] else ...[
            // No birthday connected currently
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add Birthday',
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        isBirthdayDisconnected = false;
                        isNewBirthday = true;
                        birthdayDate = DateTime.now();
                        birthdayTitleController.text = isPooja
                            ? "Queen Pooja's Birthday"
                            : "Queen Rashmika's Birthday";
                        selectedBirthdayEvent = Event(
                          id: '',
                          title: birthdayTitleController.text,
                          description: '',
                          date: birthdayDate!,
                          time: const TimeOfDay(hour: 0, minute: 0),
                          createdBy: 'Admin',
                          userId: '',
                          isRecurring: true,
                          connectedGroupId: widget.group.groupId,
                          connectedGroupName: widget.group.name,
                          connectedGroupPic: widget.group.groupPic,
                          connectedQueendom: selectedQueendom,
                        );
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label: const Text('Connect Existing',
                        style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      side:
                          BorderSide(color: accentColor.withValues(alpha: 0.6)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _showExistingBirthdayPicker(context),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showExistingBirthdayPicker(BuildContext context) async {
    final isPooja = selectedQueendom == 'Queen Pooja';
    final accentColor =
        isPooja ? const Color(0xFFFFD700) : const Color(0xFFFF4081);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161324),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StreamBuilder<List<Event>>(
          stream: ref.watch(eventRepositoryProvider).eventsStream(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final events = snapshot.data ?? [];
            final filtered = events.where((e) {
              if (e.connectedQueendom != null &&
                  e.connectedQueendom!.isNotEmpty) {
                return e.connectedQueendom == selectedQueendom;
              }
              return true;
            }).toList();

            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cake_outlined,
                        size: 40, color: accentColor.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    const Text(
                      'No existing birthday events found',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          isBirthdayDisconnected = false;
                          isNewBirthday = true;
                          birthdayDate = DateTime.now();
                          birthdayTitleController.text = isPooja
                              ? "Queen Pooja's Birthday"
                              : "Queen Rashmika's Birthday";
                          selectedBirthdayEvent = Event(
                            id: '',
                            title: birthdayTitleController.text,
                            description: '',
                            date: birthdayDate!,
                            time: const TimeOfDay(hour: 0, minute: 0),
                            createdBy: 'Admin',
                            userId: '',
                            isRecurring: true,
                            connectedGroupId: widget.group.groupId,
                            connectedGroupName: widget.group.name,
                            connectedGroupPic: widget.group.groupPic,
                            connectedQueendom: selectedQueendom,
                          );
                        });
                      },
                      child: const Text('Create New Birthday'),
                    ),
                  ],
                ),
              );
            }

            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Text(
                          'Select Birthday Event',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final ev = filtered[i];
                        final isSelected = selectedBirthdayEvent?.id == ev.id;
                        final isLinkedElsewhere = ev.connectedGroupId != null &&
                            ev.connectedGroupId!.isNotEmpty &&
                            ev.connectedGroupId != widget.group.groupId;

                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: isSelected
                                  ? accentColor
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          tileColor: isSelected
                              ? accentColor.withValues(alpha: 0.1)
                              : Colors.white.withValues(alpha: 0.03),
                          leading: CircleAvatar(
                            backgroundColor: accentColor.withValues(alpha: 0.2),
                            child:
                                Icon(Icons.cake, color: accentColor, size: 20),
                          ),
                          title: Text(
                            ev.title,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            '${DateFormat('d MMMM').format(ev.date)}${ev.isRecurring ? ' • Annual' : ''}${isLinkedElsewhere ? ' • Linked to ${ev.connectedGroupName ?? 'another group'}' : ''}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 11,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(Icons.check_circle, color: accentColor)
                              : null,
                          onTap: () {
                            Navigator.pop(ctx);
                            setState(() {
                              isBirthdayDisconnected = false;
                              isNewBirthday = false;
                              selectedBirthdayEvent = ev;
                              birthdayTitleController.text = ev.title;
                              birthdayDate = ev.date;
                              isRecurringBirthday = ev.isRecurring;
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
