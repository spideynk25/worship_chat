import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/models/chat_contact.dart';

final selectedGroupContacts = StateProvider<List<ChatContact>>((ref) => []);

class SelectContactsGroup extends ConsumerStatefulWidget {
  final List<String>? initialMemberUids;
  final String? parentGroupName;
  final double? height;
  final Color? accentColor;

  const SelectContactsGroup({
    super.key,
    this.initialMemberUids,
    this.parentGroupName,
    this.height,
    this.accentColor,
  });

  @override
  ConsumerState<SelectContactsGroup> createState() =>
      _SelectContactsGroupState();
}

class _SelectContactsGroupState extends ConsumerState<SelectContactsGroup> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _hasAutoPreselected = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleContact(ChatContact contact) {
    final currentList = ref.read(selectedGroupContacts);
    final isSelected = currentList.any((c) => c.uid == contact.uid);

    if (isSelected) {
      ref.read(selectedGroupContacts.notifier).update(
            (state) => state.where((c) => c.uid != contact.uid).toList(),
          );
    } else {
      ref.read(selectedGroupContacts.notifier).update(
            (state) => [...state, contact],
          );
    }
  }

  void _selectAll(List<ChatContact> visibleContacts, List<ChatContact> allContacts) {
    final currentList = ref.read(selectedGroupContacts);
    final targets = visibleContacts.isNotEmpty ? visibleContacts : allContacts;
    final allSelected = targets.isNotEmpty &&
        targets.every((c) => currentList.any((s) => s.uid == c.uid));

    if (allSelected) {
      // Deselect these contacts
      final targetUids = targets.map((c) => c.uid).toSet();
      ref.read(selectedGroupContacts.notifier).update(
            (state) => state.where((c) => !targetUids.contains(c.uid)).toList(),
          );
    } else {
      // Select all
      final existingUids = currentList.map((c) => c.uid).toSet();
      final toAdd = targets.where((c) => !existingUids.contains(c.uid)).toList();
      ref.read(selectedGroupContacts.notifier).update(
            (state) => [...state, ...toAdd],
          );
    }
  }

  void _selectDeityMembers(List<ChatContact> allContacts) {
    if (widget.initialMemberUids == null || widget.initialMemberUids!.isEmpty) return;

    final deityUids = widget.initialMemberUids!.toSet();
    final deityContacts =
        allContacts.where((c) => deityUids.contains(c.uid)).toList();

    final currentList = ref.read(selectedGroupContacts);
    final existingUids = currentList.map((c) => c.uid).toSet();
    final toAdd =
        deityContacts.where((c) => !existingUids.contains(c.uid)).toList();

    ref.read(selectedGroupContacts.notifier).update(
          (state) => [...state, ...toAdd],
        );
  }

  void _clearAll() {
    ref.read(selectedGroupContacts.notifier).state = [];
  }

  void _maybeAutoPreselect(List<ChatContact> contacts) {
    if (_hasAutoPreselected) return;
    if (widget.initialMemberUids == null || widget.initialMemberUids!.isEmpty) return;

    _hasAutoPreselected = true;
    final deityUids = widget.initialMemberUids!.toSet();
    final deityContacts =
        contacts.where((c) => deityUids.contains(c.uid)).toList();

    if (deityContacts.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final current = ref.read(selectedGroupContacts);
          if (current.isEmpty) {
            ref.read(selectedGroupContacts.notifier).state = deityContacts;
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? tabColor;
    final selectedContacts = ref.watch(selectedGroupContacts);
    final selectedUids = selectedContacts.map((c) => c.uid).toSet();

    return StreamBuilder<List<ChatContact>>(
      initialData: ref
          .watch(chatControllerProvider)
          .getCachedContacts(isAllChats: true),
      stream: ref.watch(chatControllerProvider).fetchAllContacts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            (!snapshot.hasData || snapshot.data!.isEmpty)) {
          return const SizedBox(
            height: 200,
            child: ContactListSkeleton(),
          );
        }

        final allContacts = snapshot.data ?? [];
        if (allContacts.isEmpty) {
          // Graceful fallback to chat contacts if users collection stream is empty
          return StreamBuilder<List<ChatContact>>(
            stream: ref.watch(chatControllerProvider).chatContacts(),
            builder: (ctx, fallbackSnap) {
              final fallbackContacts = fallbackSnap.data ?? [];
              if (fallbackContacts.isEmpty) {
                return Container(
                  height: widget.height ?? 220,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Text(
                    "No Contacts Found",
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                );
              }
              return _buildContent(
                context,
                fallbackContacts,
                selectedContacts,
                selectedUids,
                accent,
              );
            },
          );
        }

        _maybeAutoPreselect(allContacts);

        return _buildContent(
          context,
          allContacts,
          selectedContacts,
          selectedUids,
          accent,
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<ChatContact> allContacts,
    List<ChatContact> selectedContacts,
    Set<String> selectedUids,
    Color accent,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    final visibleContacts = query.isEmpty
        ? allContacts
        : allContacts
            .where((c) => c.name.toLowerCase().contains(query))
            .toList();

    final allVisibleSelected = visibleContacts.isNotEmpty &&
        visibleContacts.every((c) => selectedUids.contains(c.uid));
    final hasDeityMembers = widget.initialMemberUids != null &&
        widget.initialMemberUids!.isNotEmpty;

    final containerHeight = widget.height ?? 380.0;

    return Container(
      height: containerHeight,
      decoration: BoxDecoration(
        color: Colors.grey[950],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header Bar ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        '${selectedContacts.length} / ${allContacts.length} selected',
                        style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),

                    // Select All / Deselect All Button
                    InkWell(
                      onTap: () => _selectAll(visibleContacts, allContacts),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: allVisibleSelected
                              ? Colors.redAccent.withValues(alpha: 0.18)
                              : accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: allVisibleSelected
                                ? Colors.redAccent.withValues(alpha: 0.5)
                                : accent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              allVisibleSelected
                                  ? Icons.deselect_rounded
                                  : Icons.select_all_rounded,
                              size: 14,
                              color: allVisibleSelected
                                  ? Colors.redAccent
                                  : accent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              allVisibleSelected
                                  ? 'Deselect All'
                                  : 'Select Everything',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: allVisibleSelected
                                    ? Colors.redAccent
                                    : accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (selectedContacts.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: _clearAll,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                // Quick Deity Members Shortcut (if sub-group creation)
                if (hasDeityMembers) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _selectDeityMembers(allContacts),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.purpleAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.purpleAccent
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.auto_awesome,
                                  size: 13,
                                  color: Colors.purpleAccent,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Select All ${widget.parentGroupName ?? "Deity"} Members',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.purpleAccent,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // Search field
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search members...',
                      hintStyle: const TextStyle(
                        fontSize: 12,
                        color: Colors.white38,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 16,
                        color: Colors.white54,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                size: 14,
                                color: Colors.white54,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 0,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Contacts List ─────────────────────────────────────────
          Expanded(
            child: visibleContacts.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isNotEmpty
                          ? 'No matching members found'
                          : 'No contacts available',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: visibleContacts.length,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemBuilder: (context, index) {
                      final contact = visibleContacts[index];
                      final isSelected = selectedUids.contains(contact.uid);
                      final isDeityMember = widget.initialMemberUids != null &&
                          widget.initialMemberUids!.contains(contact.uid);

                      return InkWell(
                        onTap: () => _toggleContact(contact),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? accent.withValues(alpha: 0.08)
                                : Colors.transparent,
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.white.withValues(alpha: 0.03),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Avatar
                              UserAvatar(
                                url: contact.profilePic,
                                radius: 18,
                                borderColor: isSelected ? accent : Colors.white12,
                              ),
                              const SizedBox(width: 12),

                              // Name & badge
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      contact.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.white70,
                                      ),
                                    ),
                                    if (isDeityMember)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          '${widget.parentGroupName ?? "Deity"} Member',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: accent.withValues(alpha: 0.75),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              // Checkmark icon
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? accent
                                      : Colors.white.withValues(alpha: 0.08),
                                  border: Border.all(
                                    color: isSelected
                                        ? accent
                                        : Colors.white24,
                                    width: 1.5,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        size: 15,
                                        color: Colors.black,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
