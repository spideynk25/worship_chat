import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/features/group/utils/group_template_helper.dart';
import 'package:worship_chat/models/group.dart';

class DynamicTextWidget extends StatefulWidget {
  const DynamicTextWidget({super.key});

  /// Cleans wish text by removing bowing emojis, skin tone modifiers,
  /// and stray Fitzpatrick swatches to ensure pristine typography in AppBar subtitle.
  static String cleanWish(String raw) {
    var text = raw.trim();

    // Comprehensive regex that strips all bowing emoji variants (with/without skin tones,
    // gender modifiers, ZWJ sequences) and any stray Fitzpatrick skin tone swatches (U+1F3FB to U+1F3FF)
    // which cause the tan/peach colored square glitch.
    final emojiPattern = RegExp(
      r'[\u{1F647}\u{1F64F}](?:[\u{1F3FB}-\u{1F3FF}])?(?:\u{200D}[\u{2640}\u{2642}]\u{FE0F}?)?'
      r'|[\u{1F3FB}-\u{1F3FF}]'
      r'|[\u{200D}\u{FE0F}\u{2640}\u{2642}]',
      unicode: true,
    );

    text = text.replaceAll(emojiPattern, '');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  @override
  State<DynamicTextWidget> createState() => _DynamicTextWidgetState();
}

class _DynamicTextWidgetState extends State<DynamicTextWidget> {
  /// Base list of wishes for all predefined Queendom deities to ensure all
  /// are present immediately from initial frame or when offline.
  static const List<String> _defaultWishes = [
    // Core Supreme Goddesses
    'Long live Core Supreme Goddess Deepika',
    'Long live Core Supreme Goddess Shraddha',
    // Supreme Goddesses
    'Long live Supreme Goddess Disha',
    'Long live Supreme Goddess Kiara',
    'Long live Supreme Divine Goddess Taapsee',
    // Queens
    'Hail Queen Pooja',
    'Hail Queen Rashmika',
    'Hail Queen Priyanka',
    'Hail Queen Anupama',
    // Goddesses
    'Goddess Samantha be praised',
    'Goddess Tamannaah be praised',
    'Eternal Goddess Keerthy be praised',
    'Eternal Goddess Kajal be praised',
    // Demi Goddesses
    'Demi Goddess Raasi be praised',
    'Demi Goddess Rakul be praised',
    // Princesses
    'Hail First Born Eternal Princess Ananya',
    'Hail Second Born Eternal Princess Anikha',
    'Hail First Born Eternal Princess Ivana',
    'Hail Second Born Eternal Princess Priya',
    'Hail First Born Princess Sreeleela',
    'Hail Second Born Princess Preity',
    'Hail First Born Princess Krithi',
    'Hail Second Born Princess Mamitha',
  ];

  late List<String> _currentList;
  int _currentIndex = 0;
  Timer? _timer;
  StreamSubscription<QuerySnapshot>? _firestoreSub;

  @override
  void initState() {
    super.initState();
    _currentList = List<String>.from(_defaultWishes);
    _loadCachedAndStreamGroups();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || _currentList.isEmpty) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _currentList.length;
      });
    });
  }

  void _loadCachedAndStreamGroups() {
    // 1. Immediately read all cached groups from Hive for instant 0ms access
    try {
      if (Hive.isBoxOpen('groups_cache')) {
        final box = Hive.box('groups_cache');
        final List<GroupModel> cachedGroups = [];
        for (final key in box.keys) {
          final val = box.get(key);
          if (val is List) {
            for (final item in val) {
              if (item is Map) {
                try {
                  cachedGroups.add(
                    GroupModel.fromMap(Map<String, dynamic>.from(item)),
                  );
                } catch (_) {}
              }
            }
          }
        }
        if (cachedGroups.isNotEmpty) {
          _updateWishesWithGroups(cachedGroups);
        }
      }
    } catch (e) {
      log('DynamicTextWidget: Note reading cached groups: $e');
    }

    // 2. Real-time stream of all deity groups from Firestore
    try {
      _firestoreSub = FirebaseFirestore.instance
          .collection('groups')
          .snapshots()
          .listen(
        (snapshot) {
          final List<GroupModel> groups = [];
          for (final doc in snapshot.docs) {
            try {
              final data = doc.data();
              groups.add(GroupModel.fromMap(data));
            } catch (_) {}
          }
          if (groups.isNotEmpty) {
            _updateWishesWithGroups(groups);
          }
        },
        onError: (e) {
          log('DynamicTextWidget: Firestore stream error: $e');
        },
      );
    } catch (e) {
      log('DynamicTextWidget: Firestore not available: $e');
    }
  }

  void _updateWishesWithGroups(List<GroupModel> groups) {
    final Set<String> seenNorm = {};
    final List<String> dynamicWishes = [];

    // Extract deity wish from each group (filtering out sub-groups to show deities)
    for (final group in groups) {
      if (group.isSubGroup || group.parentGroupId != null) continue;
      final wish = _extractWish(group);
      if (wish.isNotEmpty) {
        final norm = wish.toLowerCase();
        if (!seenNorm.contains(norm)) {
          seenNorm.add(norm);
          dynamicWishes.add(wish);
        }
      }
    }

    // Blend dynamic wishes with default wishes to ensure all deities are present
    final List<String> combined = List<String>.from(dynamicWishes);
    for (final defWish in _defaultWishes) {
      final norm = defWish.toLowerCase();
      if (!seenNorm.contains(norm)) {
        seenNorm.add(norm);
        combined.add(defWish);
      }
    }

    if (mounted && combined.isNotEmpty) {
      setState(() {
        _currentList = combined;
        if (_currentIndex >= _currentList.length) {
          _currentIndex = 0;
        }
      });
    }
  }

  String _extractWish(GroupModel group) {
    if (group.wish != null && group.wish!.trim().isNotEmpty) {
      final cleaned = DynamicTextWidget.cleanWish(group.wish!);
      if (cleaned.isNotEmpty) return cleaned;
    }

    final template = GroupTemplateHelper.generateTemplate(
      position: group.position ?? '',
      name: group.name,
      family: group.family ?? '',
    );
    if (template.wish.isNotEmpty) {
      final cleaned = DynamicTextWidget.cleanWish(template.wish);
      if (cleaned.isNotEmpty) return cleaned;
    }

    final nameWithPos = group.nameWithPosition.trim();
    if (nameWithPos.isNotEmpty) {
      return 'Hail $nameWithPos';
    }

    return '';
  }


  @override
  void dispose() {
    _timer?.cancel();
    _firestoreSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentList.isEmpty) return const SizedBox.shrink();

    final text = _currentList[_currentIndex % _currentList.length];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 700),
      transitionBuilder: (Widget child, Animation<double> animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0.0, 0.2), // gentle slide from bottom
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.linearToEaseOut),
        );

        return SlideTransition(
          position: offsetAnimation,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: Text(
        text,
        key: ValueKey<String>(text),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: accentOrange,
          fontSize: 11.5,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}
