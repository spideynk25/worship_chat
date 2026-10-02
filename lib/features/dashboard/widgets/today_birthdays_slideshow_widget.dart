import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/dashboard/repositories/event_repository.dart';
import 'package:worship_chat/features/group/screens/slide_show_screen.dart';
import 'package:worship_chat/features/group/utils/queendom_group_helper.dart';
import 'package:worship_chat/models/event.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

/// Displays today's birthday celebrants on the Dashboard with a continuous
/// auto-playing slideshow of photos from their gallery and high-resolution assets.
/// Provides a royal celebratory glassmorphism UI with story-style progress indicators
/// and no numeric counters.
class TodayBirthdaysSlideshowWidget extends ConsumerStatefulWidget {
  const TodayBirthdaysSlideshowWidget({super.key});

  @override
  ConsumerState<TodayBirthdaysSlideshowWidget> createState() =>
      _TodayBirthdaysSlideshowWidgetState();
}

class _TodayBirthdaysSlideshowWidgetState
    extends ConsumerState<TodayBirthdaysSlideshowWidget> {
  static const int _virtualInitialPage = 5000;
  static const int _virtualTotalPages = 10000;

  int _selectedCelebrantIndex = 0;
  int _currentPhotoIndex = 0;
  int _virtualCurrentIndex = _virtualInitialPage;
  late final PageController _pageController;
  Timer? _slideshowTimer;
  bool _isUserInteracting = false;

  // Cache sampled photo URLs or asset paths per event ID
  final Map<String, List<String>> _celebrantPhotos = {};
  final Map<String, List<GroupGalleryImage>> _celebrantGallery = {};
  final Set<String> _loadingEventIds = {};
  List<Event> _cachedTodayBirthdays = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _virtualInitialPage);
    _startTimer();
  }

  @override
  void dispose() {
    _slideshowTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _slideshowTimer?.cancel();
    _slideshowTimer =
        Timer.periodic(const Duration(milliseconds: 3800), (timer) {
      if (!mounted ||
          !TickerMode.valuesOf(context).enabled ||
          !_pageController.hasClients ||
          _isUserInteracting) {
        return;
      }
      final photos = _getCurrentPhotos();
      if (photos.length > 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 750),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  void _previousPhoto() {
    HapticFeedback.lightImpact();
    _slideshowTimer?.cancel();
    if (_pageController.hasClients) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
    _startTimer();
  }

  void _nextPhoto() {
    HapticFeedback.lightImpact();
    _slideshowTimer?.cancel();
    if (_pageController.hasClients) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
    _startTimer();
  }

  bool _isToday(Event event, DateTime now) {
    if (event.isRecurring) {
      if (event.date.month == now.month && event.date.day == now.day) {
        return true;
      }
    } else {
      if (event.date.year == now.year &&
          event.date.month == now.month &&
          event.date.day == now.day) {
        return true;
      }
    }
    final lowerTitle = event.title.toLowerCase();
    if (lowerTitle.contains('monthly') && event.date.day == now.day) {
      return true;
    }
    if (lowerTitle.contains('weekly') && event.date.weekday == now.weekday) {
      return true;
    }
    return false;
  }

  bool _isBirthday(Event event) {
    final lowerTitle = event.title.toLowerCase();
    return lowerTitle.contains('birth') ||
        lowerTitle.contains('bday') ||
        (event.connectedGroupId != null && event.isRecurring) ||
        (event.connectedQueendom != null && event.isRecurring);
  }

  List<String> _buildFallbackPhotos(Event event) {
    final List<String> list = [];

    if (event.connectedGroupPic != null &&
        event.connectedGroupPic!.trim().isNotEmpty) {
      list.add(event.connectedGroupPic!.trim());
    }

    final lowerTitle = event.title.toLowerCase();

    // Only load Queen assets if the event title specifically names them
    if (lowerTitle.contains('pooja')) {
      list.addAll(const [
        'assets/auth_images/queen_pooja.png',
        'assets/auth_images/queen_pooja1.png',
        'assets/auth_images/queen_pooja2.png',
      ]);
    } else if (lowerTitle.contains('rashmika')) {
      list.addAll(const [
        'assets/auth_images/queen_rashmika.png',
        'assets/auth_images/queen_rashmika1.png',
        'assets/auth_images/queen_rashmika2.png',
      ]);
    } else if (lowerTitle.contains('deepika')) {
      list.addAll(const [
        'assets/auth_images/supreme_goddess_deepika.png',
      ]);
    } else if (lowerTitle.contains('priyanka')) {
      list.addAll(const [
        'assets/auth_images/queen_priyanka.png',
        'assets/auth_images/queen_priyanka1.png',
      ]);
    }

    // Default celebration assets
    if (list.isEmpty) {
      list.addAll(const [
        'assets/images/img1.png',
        'assets/images/img2.png',
        'assets/images/img3.png',
      ]);
    }

    // Deduplicate
    return list.toSet().toList();
  }

  Future<void> _loadGalleryPhotosForCelebrant(Event event) async {
    if (_celebrantPhotos.containsKey(event.id) ||
        _loadingEventIds.contains(event.id)) {
      return;
    }

    _loadingEventIds.add(event.id);

    try {
      List<String> sampledPhotos = [];
      List<GroupGalleryImage> galleryImages = [];

      final groupId = event.connectedGroupId;
      if (groupId != null && groupId.isNotEmpty) {
        final snapshot = await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .collection('gallery')
            .limit(30)
            .get();

        if (snapshot.docs.isNotEmpty) {
          galleryImages = snapshot.docs.map((doc) {
            return GroupGalleryImage.fromMap(doc.data());
          }).toList();

          _celebrantGallery[event.id] = galleryImages;

          final allUrls = galleryImages
              .map((img) => img.imageUrl)
              .where((url) => url.isNotEmpty)
              .toList();

          if (allUrls.isNotEmpty) {
            allUrls.shuffle(Random());
            sampledPhotos.addAll(allUrls.take(8));
          }
        }
      }

      // If gallery had fewer than 4 photos, seamlessly append fallback assets
      if (sampledPhotos.length < 4) {
        final fallbacks = _buildFallbackPhotos(event);
        for (final fb in fallbacks) {
          if (!sampledPhotos.contains(fb)) {
            sampledPhotos.add(fb);
          }
        }
      }

      if (mounted) {
        setState(() {
          _celebrantPhotos[event.id] = sampledPhotos;
          _loadingEventIds.remove(event.id);
        });
        _startTimer();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _celebrantPhotos[event.id] = _buildFallbackPhotos(event);
          _loadingEventIds.remove(event.id);
        });
        _startTimer();
      }
    }
  }

  List<String> _getCurrentPhotos() {
    if (_cachedTodayBirthdays.isEmpty) return const [];
    final celebrant = _cachedTodayBirthdays[
        _selectedCelebrantIndex.clamp(0, _cachedTodayBirthdays.length - 1)];
    return _celebrantPhotos[celebrant.id] ?? _buildFallbackPhotos(celebrant);
  }

  Color _getQueendomAccent(String? queendom, String title) {
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.contains('pooja') || queendom == 'Queen Pooja') {
      return const Color(0xFFFFD700); // Royal Gold
    }
    if (lowerTitle.contains('rashmika') || queendom == 'Queen Rashmika') {
      return const Color(0xFFFF4081); // Hot Rose
    }
    if (lowerTitle.contains('deepika') || queendom == 'Supreme Goddess Deepika') {
      return const Color(0xFFFF9E00); // Divine Amber
    }
    if (lowerTitle.contains('priyanka') || queendom == 'Queen Priyanka') {
      return const Color(0xFFE040FB); // Royal Orchid
    }
    return tabColor;
  }

  Color _getQueendomDarkAccent(Color accent) {
    if (accent == const Color(0xFFFFD700)) return const Color(0xFFFF9500);
    if (accent == const Color(0xFFFF4081)) return const Color(0xFFD81B60);
    return const Color(0xFFC2185B);
  }

  String _extractCelebrantName(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return 'Celebrant';

    final lower = trimmed.toLowerCase();

    // If title explicitly refers to one of the Queens/Goddesses:
    if (lower.contains('pooja')) {
      return 'Queen Pooja';
    }
    if (lower.contains('rashmika')) {
      return 'Queen Rashmika';
    }
    if (lower.contains('deepika')) {
      return 'Goddess Deepika';
    }
    if (lower.contains('priyanka')) {
      return 'Queen Priyanka';
    }

    // Remove common prefixes:
    // e.g. "Birthday of Ashwin", "Bday of Ashwin", "Happy Birthday Ashwin"
    String cleaned = trimmed;
    cleaned = cleaned.replaceAll(
      RegExp(r'^(happy\s+)?(birthday|bday)\s+(of\s+)?', caseSensitive: false),
      '',
    );

    // Remove common suffixes:
    // e.g. "Ashwin's Birthday", "Ashwin's Bday", "Ashwin Birthday", "Ashwin Bday"
    cleaned = cleaned.replaceAll(
      RegExp(r"['’]s\s+(birthday|bday).*", caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r"\s+(birthday|bday).*", caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r"['’]s$", caseSensitive: false),
      '',
    );

    cleaned = cleaned.trim();
    return cleaned.isNotEmpty ? cleaned : trimmed;
  }

  String _getCelebrantShortName(Event ev) {
    return _extractCelebrantName(ev.title);
  }

  String _getPersonalizedWish(Event event) {
    final celebrantName = _extractCelebrantName(event.title);
    final lowerTitle = event.title.toLowerCase();

    // If the event title specifically names a Queen, return royal greeting
    if (lowerTitle.contains('pooja')) {
      return 'Wishing Her Supreme Royal Majesty Queen Pooja an extraordinary day filled with eternal grace, immense devotion, and boundless joy! 👑🎂✨';
    } else if (lowerTitle.contains('rashmika')) {
      return 'Wishing Her Divine Grace Queen Rashmika a radiant and heartwarming birthday filled with smiles, happiness, and endless love! 💖🎂✨';
    } else if (lowerTitle.contains('deepika')) {
      return 'Wishing Her Supreme Highness Deepika a majestic birthday brimming with divine blessings, glory, and prosperity! ✨🎂👑';
    } else if (lowerTitle.contains('priyanka')) {
      return 'Wishing Her Majestic Highness Queen Priyanka a magnificent birthday filled with splendor, elegance, and endless celebration! 💜🎂✨';
    }

    // Check if event.description has a custom wish
    final desc = event.description.trim();
    if (desc.isNotEmpty) {
      final lowerDesc = desc.toLowerCase();
      // Guard against old stale Queen wishes saved by previous bugs for non-queen events
      final hasQueenMismatch = lowerDesc.contains('queen pooja') ||
          lowerDesc.contains('queen rashmika') ||
          lowerDesc.contains('supreme goddess') ||
          lowerDesc.contains('her supreme royal majesty') ||
          lowerDesc.contains('her divine grace');
      if (!hasQueenMismatch) {
        return desc;
      }
    }

    return 'Wishing $celebrantName a truly wonderful and blessed birthday! May your year ahead be full of celebration, happiness, and boundless joy! 🎉🎂✨';
  }

  void _onCelebrantTabSelected(int index) {
    if (index == _selectedCelebrantIndex) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedCelebrantIndex = index;
      _currentPhotoIndex = 0;
    });
    final photos = _getCurrentPhotos();
    if (photos.isNotEmpty && _pageController.hasClients) {
      final base = (_virtualInitialPage ~/ photos.length) * photos.length;
      _virtualCurrentIndex = base;
      _pageController.jumpToPage(_virtualCurrentIndex);
    }
    _startTimer();
  }

  void _openFullSlideshow(
    BuildContext context,
    Event celebrant,
    List<String> photos,
    Color accentColor,
  ) {
    HapticFeedback.selectionClick();
    final galleryList = _celebrantGallery[celebrant.id] ?? const [];

    if (galleryList.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SlideshowScreen(
            images: galleryList,
            initialIndex:
                _currentPhotoIndex.clamp(0, galleryList.length - 1),
            accentColor: accentColor,
            groupName: celebrant.connectedGroupName ?? celebrant.title,
          ),
        ),
      );
    } else {
      // Create synthetic gallery items from available photos
      final synthImages = photos.asMap().entries.map((entry) {
        return GroupGalleryImage(
          imageId: 'bday_${celebrant.id}_${entry.key}',
          groupId: celebrant.connectedGroupId ?? 'general',
          imageUrl: entry.value,
          uploadedBy: 'Birthday Showcase',
          uploadedByName: celebrant.connectedGroupName ?? _getCelebrantShortName(celebrant),
          uploadedAt: DateTime.now(),
        );
      }).toList();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SlideshowScreen(
            images: synthImages,
            initialIndex:
                _currentPhotoIndex.clamp(0, synthImages.length - 1),
            accentColor: accentColor,
            groupName: celebrant.connectedGroupName ?? celebrant.title,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventsStream = ref.watch(eventRepositoryProvider).eventsStream();

    return StreamBuilder<List<Event>>(
      stream: eventsStream,
      builder: (context, snapshot) {
        final allEvents = snapshot.data ?? [];
        final now = DateTime.now();
        final todayBirthdays = allEvents
            .where((e) => _isToday(e, now) && _isBirthday(e))
            .toList();

        _cachedTodayBirthdays = todayBirthdays;

        if (todayBirthdays.isEmpty) {
          return const SizedBox.shrink();
        }

        // Clamp index safely
        if (_selectedCelebrantIndex >= todayBirthdays.length) {
          _selectedCelebrantIndex = 0;
        }

        final currentCelebrant = todayBirthdays[_selectedCelebrantIndex];
        final accentColor = _getQueendomAccent(
          currentCelebrant.connectedQueendom,
          currentCelebrant.title,
        );

        // Preload photos for active celebrant
        _loadGalleryPhotosForCelebrant(currentCelebrant);

        // Preload for other celebrants in the background if multiple
        for (final ev in todayBirthdays) {
          _loadGalleryPhotosForCelebrant(ev);
        }

        final photos = _getCurrentPhotos();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accentColor.withValues(alpha: 0.16),
                const Color(0xFF140E22),
                const Color(0xFF0C0916),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.55),
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.22),
                blurRadius: 28,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 18,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: Title & Multi-Celebrant Selector ────────────────
              _buildHeader(todayBirthdays, currentCelebrant, accentColor),

              // ── Slideshow Showcase ─────────────────────────────────────
              _buildSlideshowArea(currentCelebrant, photos, accentColor),

              // ── Birthday Wish & Action Buttons ─────────────────────────
              _buildWishAndActions(currentCelebrant, photos, accentColor),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    List<Event> todayBirthdays,
    Event currentCelebrant,
    Color accentColor,
  ) {
    final celebrantName = _getCelebrantShortName(currentCelebrant);
    final lowerTitle = currentCelebrant.title.toLowerCase();
    final isQueen = lowerTitle.contains('pooja') ||
        lowerTitle.contains('rashmika') ||
        lowerTitle.contains('deepika') ||
        lowerTitle.contains('priyanka');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Glowing Celebration Icon Badge
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accentColor,
                      accentColor.withValues(alpha: 0.7),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  isQueen ? '👑' : '🎂',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              const SizedBox(width: 10),
              // Header Title Stack
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isQueen
                          ? 'ROYAL BIRTHDAY CELEBRATION'
                          : 'TODAY\'S BIRTHDAY CELEBRATION',
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '$celebrantName\'s Birthday ✨',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        height: 1.25,
                      ),
                      maxLines: 3,
                      softWrap: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Today Chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.75),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.25),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🎉', style: TextStyle(fontSize: 11)),
                    SizedBox(width: 4),
                    Text(
                      'TODAY',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Horizontal selector chips ("clip cards") for celebrants
          if (todayBirthdays.length > 1) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: todayBirthdays.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final ev = todayBirthdays[index];
                  final isSelected = index == _selectedCelebrantIndex;
                  final evColor = _getQueendomAccent(
                    ev.connectedQueendom,
                    ev.title,
                  );
                  final name = _getCelebrantShortName(ev);

                  return GestureDetector(
                    onTap: () => _onCelebrantTabSelected(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? LinearGradient(
                                colors: [
                                  evColor.withValues(alpha: 0.4),
                                  evColor.withValues(alpha: 0.15),
                                ],
                              )
                            : null,
                        color: isSelected
                            ? null
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? evColor
                              : Colors.white.withValues(alpha: 0.16),
                          width: isSelected ? 1.5 : 0.8,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: evColor.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isSelected ? '👑' : '🎂',
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            name,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSlideshowArea(
    Event currentCelebrant,
    List<String> photos,
    Color accentColor,
  ) {
    final celebrantName = _getCelebrantShortName(currentCelebrant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. Clean Photo Container (Zero overlays on photo, original size) ──
        Container(
          height: 350,
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF090612), // Deep elegant backdrop
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.3),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification) {
                  _isUserInteracting = true;
                } else if (notification is ScrollEndNotification) {
                  _isUserInteracting = false;
                  _startTimer();
                }
                return false;
              },
              child: PageView.builder(
                controller: _pageController,
                itemCount: photos.isEmpty ? 0 : _virtualTotalPages,
                onPageChanged: (idx) {
                  if (photos.isEmpty) return;
                  _virtualCurrentIndex = idx;
                  final realIdx = idx % photos.length;
                  if (_currentPhotoIndex != realIdx) {
                    setState(() => _currentPhotoIndex = realIdx);
                  }
                },
                itemBuilder: (context, index) {
                  if (photos.isEmpty) {
                    return Center(
                      child: Icon(
                        Icons.cake_rounded,
                        size: 48,
                        color: accentColor.withValues(alpha: 0.5),
                      ),
                    );
                  }
                  final photo = photos[index % photos.length];
                  final isNetwork = photo.startsWith('http://') ||
                      photo.startsWith('https://');

                  // Entire photo shown cleanly with BoxFit.contain
                  // ABSOLUTELY NOTHING placed on top of the photo!
                  return GestureDetector(
                    onTap: () => _openFullSlideshow(
                      context,
                      currentCelebrant,
                      photos,
                      accentColor,
                    ),
                    child: Center(
                      child: isNetwork
                          ? CachedNetworkImage(
                              imageUrl: photo,
                              fit: BoxFit.contain,
                              placeholder: (context, url) => Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Image.asset(
                                'assets/images/img1.png',
                                fit: BoxFit.contain,
                              ),
                            )
                          : Image.asset(
                              photo,
                              fit: BoxFit.contain,
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // ── 2. Information & Controls (Placed completely BELOW the photo) ─────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 2),
          child: Row(
            children: [
              // Celebrant Name and Event Title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      celebrantName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      softWrap: true,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currentCelebrant.title,
                      style: TextStyle(
                        color: accentColor.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      softWrap: true,
                    ),
                  ],
                ),
              ),

              // Navigation & Photo count indicator (completely below photo)
              if (photos.length > 1) ...[
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _previousPhoto,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 0.8,
                        ),
                      ),
                      child: const Icon(
                        Icons.chevron_left_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    '${_currentPhotoIndex + 1} / ${photos.length}',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _nextPhoto,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 0.8,
                        ),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWishAndActions(
    Event currentCelebrant,
    List<String> photos,
    Color accentColor,
  ) {
    final wishText = _getPersonalizedWish(currentCelebrant);
    final darkAccent = _getQueendomDarkAccent(accentColor);
    final celebrantName = _getCelebrantShortName(currentCelebrant);
    final lowerTitle = currentCelebrant.title.toLowerCase();
    final isQueen = lowerTitle.contains('pooja') ||
        lowerTitle.contains('rashmika') ||
        lowerTitle.contains('deepika') ||
        lowerTitle.contains('priyanka');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Wish Greeting Quote Card ─────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accentColor.withValues(alpha: 0.12),
                  const Color(0xFF1D152C).withValues(alpha: 0.75),
                  const Color(0xFF120C1E).withValues(alpha: 0.85),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '“',
                      style: TextStyle(
                        fontSize: 26,
                        height: 0.75,
                        color: accentColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        wishText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    isQueen
                        ? '👑 Royal Devotion & Joy ✨'
                        : '🎉 Happy Birthday $celebrantName ✨',
                    style: TextStyle(
                      color: accentColor.withValues(alpha: 0.85),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    softWrap: true,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Action Buttons ───────────────────────────────────────────
          Row(
            children: [
              // Primary "Wish in Group" / "Copy Wish" Button
              Expanded(
                flex: 6,
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accentColor, darkAccent],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.black,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      if (currentCelebrant.connectedGroupId != null) {
                        navigateToQueendomGroup(
                          context,
                          groupId: currentCelebrant.connectedGroupId!,
                          name: currentCelebrant.connectedGroupName ??
                              'Queendom Group',
                          groupPic: currentCelebrant.connectedGroupPic,
                          queendom: currentCelebrant.connectedQueendom,
                          wish: currentCelebrant.description.isNotEmpty
                              ? currentCelebrant.description
                              : wishText,
                        );
                      } else {
                        Clipboard.setData(ClipboardData(text: wishText));
                        AppSnackBar.success(
                          context,
                          'Birthday Wish for $celebrantName copied to clipboard! 🎂✨',
                          customIcon: Icons.cake_rounded,
                        );
                      }
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isQueen ? '👑' : '🎂',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          currentCelebrant.connectedGroupId != null
                              ? 'Wish in Group'
                              : 'Copy Birthday Wish',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Secondary "Gallery" Button
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      side: BorderSide(
                        color: accentColor.withValues(alpha: 0.38),
                        width: 1.2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _openFullSlideshow(
                      context,
                      currentCelebrant,
                      photos,
                      accentColor,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          size: 15,
                          color: accentColor,
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Gallery',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
