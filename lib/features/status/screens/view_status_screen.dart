import 'dart:async';
import 'dart:developer';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/status/controller/status_controller.dart';
import 'package:worship_chat/models/user_model.dart';

class ViewStatusesScreen extends ConsumerStatefulWidget {
  static const String routeName = '/view-status-screen';
  final List<Map<String, dynamic>> statuses;
  final int initialIndex;

  const ViewStatusesScreen({
    super.key,
    required this.statuses,
    required this.initialIndex,
  });

  @override
  ConsumerState<ViewStatusesScreen> createState() => _ViewStatusesScreenState();
}

class _ViewStatusesScreenState extends ConsumerState<ViewStatusesScreen>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  late int _currentIndex;
  late List<AnimationController> _progressControllers;

  VideoPlayerController? _videoController;
  bool _videoReady = false;
  bool _muted = false;

  VoidCallback? _videoProgressListener;
  Timer? _slideTimer;
  bool _isAdvancing = false;

  // ── Reply state ───────────────────────────────────────────────────────────
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  bool _replyFieldVisible = false;
  bool _isSendingReply = false;

  late final String _currentUserUid;
  late final String _currentUserName;
  late final String _currentUserProfilePic;

  static const _imageDuration = Duration(seconds: 8);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final user = FirebaseAuth.instance.currentUser!;
    _currentUserUid = user.uid;
    _currentUserName = user.displayName ?? 'Unknown';

    // Prefer Hive profile pic (most up-to-date)
    _currentUserProfilePic =
        Hive.box<UserModel>('userBox').get('currentUser')?.profilePic ??
        user.photoURL ??
        '';

    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    _progressControllers = List.generate(
      widget.statuses.length,
      (_) => AnimationController(vsync: this, duration: _imageDuration),
    );

    // Pause when reply field gains focus, resume on unfocus
    _replyFocusNode.addListener(() {
      if (_replyFocusNode.hasFocus) {
        _pauseAll();
      } else {
        if (_replyController.text.isEmpty) {
          setState(() => _replyFieldVisible = false);
        }
        _resumeAll();
      }
    });

    _startSlide(_currentIndex);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _cancelTimer();
    _pageController.dispose();
    for (final c in _progressControllers) c.dispose();
    _cleanupVideoController(_videoController);
    _videoController = null;
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _isVideo(int index) =>
      (widget.statuses[index]['mediaType'] as String?) == 'video';

  void _cancelTimer() {
    _slideTimer?.cancel();
    _slideTimer = null;
  }

  void _cleanupVideoController(VideoPlayerController? vc) {
    if (vc == null) return;
    if (_videoProgressListener != null) {
      vc.removeListener(_videoProgressListener!);
      _videoProgressListener = null;
    }
    vc.pause().then((_) => vc.dispose()).catchError((_) {});
  }

  // ── Slide lifecycle ───────────────────────────────────────────────────────

  Future<void> _startSlide(int index) async {
    _isAdvancing = false;
    _cancelTimer();

    final oldVc = _videoController;
    _videoController = null;
    _videoReady = false;
    _cleanupVideoController(oldVc);

    for (int i = 0; i < _progressControllers.length; i++) {
      _progressControllers[i].stop();
      if (i < index) {
        _progressControllers[i].value = 1.0;
      } else if (i > index) {
        _progressControllers[i].value = 0.0;
      }
    }

    if (!mounted) return;

    _markAsSeen(widget.statuses[index]);

    if (_isVideo(index)) {
      await _initVideo(index);
    } else {
      _startImageSlide(index);
    }
  }

  void _startImageSlide(int index) {
    if (!mounted) return;
    final pc = _progressControllers[index];
    pc.duration = _imageDuration;
    pc.forward(from: 0);
    _slideTimer = Timer(_imageDuration, () {
      if (mounted && index == _currentIndex && !_isAdvancing) _goToNext();
    });
  }

  Future<void> _initVideo(int index) async {
    if (!mounted) return;
    final url = widget.statuses[index]['statusUrl'] as String;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _videoController = controller;
    if (mounted) setState(() => _videoReady = false);

    try {
      await controller.initialize();
    } catch (e) {
      debugPrint('Video init error: $e');
      if (_videoController == controller) _videoController = null;
      _cleanupVideoController(controller);
      if (mounted && index == _currentIndex) {
        _slideTimer = Timer(const Duration(seconds: 1), () {
          if (mounted && index == _currentIndex) _goToNext();
        });
      }
      return;
    }

    if (!mounted || _videoController != controller) {
      _cleanupVideoController(controller);
      return;
    }

    final videoDuration = controller.value.duration;
    final slideDuration = videoDuration.inMilliseconds > 0
        ? videoDuration
        : _imageDuration;
    final pc = _progressControllers[index];
    pc.duration = slideDuration;

    _videoProgressListener = () {
      if (!mounted) return;
      final vc = _videoController;
      if (vc == null || !vc.value.isInitialized) return;
      final total = vc.value.duration.inMilliseconds;
      if (total <= 0) return;
      final progress = (vc.value.position.inMilliseconds / total).clamp(
        0.0,
        1.0,
      );
      if (progress > pc.value) pc.value = progress;
    };
    controller.addListener(_videoProgressListener!);
    controller.setVolume(_muted ? 0 : 1);
    await controller.play();

    if (!mounted || _videoController != controller) {
      _cleanupVideoController(controller);
      return;
    }

    setState(() => _videoReady = true);
    pc.forward(from: 0);

    _slideTimer = Timer(slideDuration, () {
      if (!mounted || index != _currentIndex || _isAdvancing) return;
      _detachVideoBeforeAdvance();
      _goToNext();
    });
  }

  void _detachVideoBeforeAdvance() {
    final vc = _videoController;
    _videoController = null;
    _videoReady = false;
    if (mounted) setState(() {});
    _cleanupVideoController(vc);
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _goToNext() {
    if (!mounted || _isAdvancing) return;
    _isAdvancing = true;
    _cancelTimer();
    if (_currentIndex < widget.statuses.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _goToPrev() {
    if (!mounted) return;
    _cancelTimer();
    _isAdvancing = false;
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _pauseAll() {
    _cancelTimer();
    _progressControllers[_currentIndex].stop();
    _videoController?.pause();
  }

  void _resumeAll() {
    if (!mounted || _replyFocusNode.hasFocus) return;
    final pc = _progressControllers[_currentIndex];
    final elapsed = pc.duration! * pc.value;
    final remaining = pc.duration! - elapsed;
    _videoController?.play();
    pc.forward();
    _slideTimer = Timer(remaining, () {
      if (!mounted || _isAdvancing) return;
      if (_isVideo(_currentIndex)) _detachVideoBeforeAdvance();
      _goToNext();
    });
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _videoController?.setVolume(_muted ? 0 : 1);
  }

  void _markAsSeen(Map<String, dynamic> status) {
    final ownerUid = status['uid'] as String? ?? '';
    if (ownerUid == _currentUserUid) return;
    ref
        .read(statusControllerProvider)
        .markStatusAsSeen(
          statusId: status['statusId'] as String,
          viewerUid: _currentUserUid,
          viewerName: _currentUserName,
          viewerProfilePic: _currentUserProfilePic,
        );
  }

  void _showViewers() {
    final statusId = widget.statuses[_currentIndex]['statusId'] as String;
    _pauseAll();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ViewersSheet(statusId: statusId),
    ).whenComplete(() {
      if (mounted) _resumeAll();
    });
  }

  // ── Like handler ──────────────────────────────────────────────────────────

  Future<void> _handleLike() async {
    final status = widget.statuses[_currentIndex];
    final statusOwnerUid = status['uid'] as String;

    await ref
        .read(statusControllerProvider)
        .toggleLike(
          statusId: status['statusId'] as String,
          likerUid: _currentUserUid,
          likerName: _currentUserName,
          likerProfilePic: _currentUserProfilePic,
        );

    // Notify the story owner
    Future.microtask(() async {
      try {
        final ownerUser = await ref
            .read(authControllerProvider)
            .userDataById(statusOwnerUid)
            .first;
        final dynamic u = ownerUser;
        final fcmToken =
            (u.fcmToken as String?) ??
            (u.token as String?) ??
            (u.pushToken as String?) ??
            '';
        if (fcmToken.isEmpty) return;

        await sendNotification(
          fcmToken,
          '❤️ $_currentUserName liked your story',
          'Tap to view your story',
        );
      } catch (e) {
        log('Like notification error: $e');
      }
    });
  }

  // ── Reply handler ─────────────────────────────────────────────────────────

  void _openReply() {
    setState(() => _replyFieldVisible = true);
    Future.delayed(const Duration(milliseconds: 80), () {
      _replyFocusNode.requestFocus();
    });
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSendingReply = true);
    _replyController.clear();
    _replyFocusNode.unfocus();

    final status = widget.statuses[_currentIndex];
    final statusOwnerUid = status['uid'] as String;
    final statusUrl = status['statusUrl'] as String;
    final ownerName = status['userName'] as String;
    final isVideo = (status['mediaType'] as String?) == 'video';

    // ── Build a MessageReply so the chat bubble shows the story thumbnail ──
    // The repository reads: messageReply.message, .isMe, .messageType,
    // .fileMessageData — which maps onto repliedMessage/repliedMessageType
    // in the saved OneToOneMessageModel, rendering the story thumbnail in chat.
    final storyReply = MessageReply(
      message: statusUrl, // shown as the quoted content (image/video URL)
      isMe: false, // it's a reply TO the owner, not ourselves
      messageType: isVideo ? 'video' : 'image',
      fileMessageData: statusUrl,
    );

    // ── Inject the reply into the provider so sendTextMessage picks it up ──
    ref.read(messageReplyProvider.state).state = storyReply;

    // ── Fetch the status owner's FCM token ────────────────────────────────
    String fcmToken = '';
    try {
      final ownerUser = await ref
          .read(authControllerProvider)
          .userDataById(statusOwnerUid)
          .first;
      final dynamic u = ownerUser;
      fcmToken =
          (u.fcmToken as String?) ??
          (u.token as String?) ??
          (u.pushToken as String?) ??
          '';
    } catch (_) {}

    if (!mounted) {
      ref.read(messageReplyProvider.state).state = null;
      setState(() => _isSendingReply = false);
      return;
    }

    // ── Send — the controller reads messageReplyProvider internally ────────
    await ref
        .read(chatControllerProvider)
        .sendTextMessage(
          context,
          text,
          statusOwnerUid,
          'text',
          null,
          fcmToken,
          true,
          null,
          "others",
        );

    // Clear the reply provider after sending
    ref.read(messageReplyProvider.state).state = null;

    if (mounted) {
      setState(() {
        _isSendingReply = false;
        _replyFieldVisible = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final currentStatus = widget.statuses[_currentIndex];
    final isOwner = (currentStatus['uid'] as String?) == _currentUserUid;
    final currentIsVideo = _isVideo(_currentIndex);
    final statusId = currentStatus['statusId'] as String;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        // Tap only fires navigation when reply field is NOT focused
        onTapUp: _replyFocusNode.hasFocus
            ? null
            : (d) {
                final w = MediaQuery.of(context).size.width;
                if (d.globalPosition.dx < w * 0.35) {
                  _goToPrev();
                } else {
                  _goToNext();
                }
              },
        onLongPressStart: (_) => _pauseAll(),
        onLongPressEnd: (_) => _resumeAll(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── 1. PageView ──────────────────────────────────────────────
            PageView.builder(
              controller: _pageController,
              itemCount: widget.statuses.length,
              onPageChanged: (i) {
                setState(() {
                  _currentIndex = i;
                  _replyFieldVisible = false;
                });
                _startSlide(i);
              },
              itemBuilder: (context, index) {
                final isVid = _isVideo(index);
                final url = widget.statuses[index]['statusUrl'] as String;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!isVid)
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          color: Colors.black.withOpacity(0.4),
                          colorBlendMode: BlendMode.darken,
                          placeholder: (_, __) =>
                              const ColoredBox(color: Colors.black),
                          errorWidget: (_, __, ___) =>
                              const ColoredBox(color: Colors.black),
                        ),
                      )
                    else
                      const ColoredBox(color: Colors.black),
                    Center(
                      child: isVid
                          ? _VideoSlide(
                              controller: index == _currentIndex
                                  ? _videoController
                                  : null,
                              isReady: index == _currentIndex && _videoReady,
                            )
                          : CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white54,
                                  strokeWidth: 1.5,
                                ),
                              ),
                              errorWidget: (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white30,
                                size: 64,
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),

            // ── 2. Top scrim ─────────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topPad + 120,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── 3. Bottom scrim ──────────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 160,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── 4. Progress + top bar ────────────────────────────────────
            Positioned(
              top: topPad + 10,
              left: 0,
              right: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: List.generate(widget.statuses.length, (i) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: AnimatedBuilder(
                              animation: _progressControllers[i],
                              builder: (_, __) {
                                double val;
                                if (i < _currentIndex) {
                                  val = 1.0;
                                } else if (i == _currentIndex) {
                                  val = _progressControllers[i].value;
                                } else {
                                  val = 0.0;
                                }
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: val,
                                    minHeight: 3,
                                    backgroundColor: Colors.white.withOpacity(
                                      0.3,
                                    ),
                                    valueColor: const AlwaysStoppedAnimation(
                                      Colors.white,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 6),
                        UserAvatar(
                          url: currentStatus['profilePic'] as String?,
                          radius: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currentStatus['userName'] as String,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 8,
                                      color: Colors.black54,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                _formatTimeAgo(
                                  (currentStatus['timeCreated'] as Timestamp)
                                      .toDate(),
                                ),
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 6,
                                      color: Colors.black45,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (currentIsVideo)
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            icon: Icon(
                              _muted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: _toggleMute,
                          ),
                        if (widget.statuses.length > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_currentIndex + 1}/${widget.statuses.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── 5. Bottom actions row (like + reply / seen-by) ───────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: isOwner
                      // ── Owner: seen-by pill only ─────────────────────
                      ? Center(
                          child: GestureDetector(
                            onTap: _showViewers,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(30),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 14,
                                  sigmaY: 14,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 22,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.25),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.remove_red_eye_outlined,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        "Seen by",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      // ── Viewer: like + reply ──────────────────────────
                      : _replyFieldVisible
                      ? _buildReplyInput()
                      : _buildLikeReplyBar(statusId),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Like + reply action bar ───────────────────────────────────────────────

  Widget _buildLikeReplyBar(String statusId) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: ref.read(statusControllerProvider).getLikesStream(statusId),
      builder: (context, snapshot) {
        final likes = snapshot.data ?? {};
        final isLiked = likes.containsKey(_currentUserUid);

        return Row(
          children: [
            // ── Like button ──────────────────────────────────────────
            GestureDetector(
              onTap: isLiked ? null : _handleLike,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isLiked
                          ? Colors.red.withOpacity(0.25)
                          : Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: isLiked
                            ? Colors.red.withOpacity(0.6)
                            : Colors.white.withOpacity(0.2),
                      ),
                    ),
                    child: Icon(
                      isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: isLiked ? Colors.red : Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // ── Reply button ─────────────────────────────────────────
            Expanded(
              child: GestureDetector(
                onTap: _openReply,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.reply_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Reply',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Reply input with story preview (WhatsApp / Instagram style) ─────────

  Widget _buildReplyInput() {
    final status = widget.statuses[_currentIndex];
    final isVideo = (status['mediaType'] as String?) == 'video';
    final statusUrl = status['statusUrl'] as String;
    final ownerName = status['userName'] as String;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Story preview banner ───────────────────────────────────
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: Container(
                  height: 72,
                  color: Colors.white.withOpacity(0.06),
                  child: Row(
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                        ),
                        child: Stack(
                          children: [
                            CachedNetworkImage(
                              imageUrl: statusUrl,
                              width: 52,
                              height: 72,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                width: 52,
                                height: 72,
                                color: Colors.white10,
                              ),
                              errorWidget: (_, __, ___) => Container(
                                width: 52,
                                height: 72,
                                color: Colors.white10,
                                child: const Icon(
                                  Icons.image_outlined,
                                  color: Colors.white38,
                                  size: 20,
                                ),
                              ),
                            ),
                            // Video indicator overlay
                            if (isVideo)
                              Positioned.fill(
                                child: Container(
                                  color: Colors.black38,
                                  child: const Icon(
                                    Icons.play_circle_outline_rounded,
                                    color: Colors.white70,
                                    size: 22,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Label
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ownerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  isVideo
                                      ? Icons.videocam_rounded
                                      : Icons.image_outlined,
                                  color: Colors.white54,
                                  size: 13,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isVideo ? 'Video story' : 'Photo story',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Dismiss button
                      GestureDetector(
                        onTap: () {
                          _replyFocusNode.unfocus();
                          setState(() => _replyFieldVisible = false);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withOpacity(0.6),
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ── Divider ────────────────────────────────────────────────
              Divider(
                height: 1,
                thickness: 1,
                color: Colors.white.withOpacity(0.10),
              ),
              // ── Text field + send ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _replyController,
                        focusNode: _replyFocusNode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        maxLines: 3,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendReply(),
                        decoration: InputDecoration(
                          hintText:
                              'Reply to ${ownerName.split(' ').first}\'s story…',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 6,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Send button
                    GestureDetector(
                      onTap: _isSendingReply ? null : _sendReply,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: tabColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: tabColor.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _isSendingReply
                            ? const Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 17,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── Video slide ─────────────────────────────────────────────────────────────

class _VideoSlide extends StatelessWidget {
  final VideoPlayerController? controller;
  final bool isReady;
  const _VideoSlide({required this.controller, required this.isReady});

  @override
  Widget build(BuildContext context) {
    if (!isReady || controller == null) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: CircularProgressIndicator(
          color: Colors.white54,
          strokeWidth: 1.5,
        ),
      );
    }
    return AspectRatio(
      aspectRatio: controller!.value.aspectRatio,
      child: VideoPlayer(controller!),
    );
  }
}

// ── Viewers sheet ───────────────────────────────────────────────────────────

class _ViewersSheet extends ConsumerWidget {
  final String statusId;
  const _ViewersSheet({required this.statusId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.75,
      builder: (_, scrollController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF111111).withOpacity(0.94),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: ref
                  .read(statusControllerProvider)
                  .getStatusViewers(statusId),
              builder: (context, snapshot) {
                final viewers = snapshot.data ?? [];
                final loading =
                    snapshot.connectionState == ConnectionState.waiting;
                return Column(
                  children: [
                    Container(
                      width: 32,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: Row(
                        children: [
                          const Text(
                            "Seen by",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          if (!loading && viewers.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${viewers.length}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(
                          color: Colors.white38,
                          strokeWidth: 1.5,
                        ),
                      )
                    else if (viewers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 40,
                          horizontal: 24,
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.visibility_off_outlined,
                                color: Colors.white24,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              "No views yet",
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              "People who view your story will appear here",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white24,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: viewers.length,
                          itemBuilder: (_, i) {
                            final v = viewers[i];
                            final seenAt = v['seenAt'] as DateTime?;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Stack(
                                    children: [
                                      UserAvatar(
                                        url: v['profilePic'] as String?,
                                        radius: 22,
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: Container(
                                          width: 14,
                                          height: 14,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF34C759),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.check,
                                            color: Colors.white,
                                            size: 9,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      v['userName'] as String? ?? 'Unknown',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  if (seenAt != null)
                                    Text(
                                      DateFormat('h:mm a').format(seenAt),
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
