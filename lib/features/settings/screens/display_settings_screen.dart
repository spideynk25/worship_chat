import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/features/settings/providers/chat_bubble_settings_provider.dart';

class DisplaySettingsScreen extends ConsumerStatefulWidget {
  static const routeName = '/display-settings-screen';

  const DisplaySettingsScreen({super.key});

  @override
  ConsumerState<DisplaySettingsScreen> createState() => _DisplaySettingsScreenState();
}

class _DisplaySettingsScreenState extends ConsumerState<DisplaySettingsScreen> {
  bool _useLightWallpaper = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(chatBubbleSettingsProvider);
    final notifier = ref.read(chatBubbleSettingsProvider.notifier);

    final transparencyPercent = (settings.transparency * 100).round();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161426),
        elevation: 0,
        title: const Text(
          'Display Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: tabColor),
            tooltip: 'Reset to Default',
            onPressed: () => notifier.resetToDefault(),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF161426),
              Color(0xFF0F0E17),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Section 1: Live Interactive Preview Header with Backdrop Switch ─
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSectionHeader(
                      icon: Icons.remove_red_eye_rounded,
                      title: 'LIVE BUBBLE PREVIEW',
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _useLightWallpaper = !_useLightWallpaper;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _useLightWallpaper
                              ? const Color(0xFFFFB74D).withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _useLightWallpaper
                                ? const Color(0xFFFFB74D).withValues(alpha: 0.6)
                                : Colors.white.withValues(alpha: 0.18),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _useLightWallpaper
                                  ? Icons.light_mode_rounded
                                  : Icons.dark_mode_rounded,
                              size: 13,
                              color: _useLightWallpaper
                                  ? const Color(0xFFFFB74D)
                                  : Colors.white70,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _useLightWallpaper ? 'Light Backdrop' : 'Dark Backdrop',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _useLightWallpaper
                                    ? const Color(0xFFFFB74D)
                                    : Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildLivePreviewCard(settings),

                // Adaptive contrast explanation note
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 12, color: tabColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Bubble colors are eye-friendly across all opacity levels. Text automatically adapts for high-contrast readability against any background.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.50),
                            fontSize: 10.5,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // ── Section 2: Transparency Slider Control ───────────────────
                _buildSectionHeader(
                  icon: Icons.tune_rounded,
                  title: 'CHAT BUBBLE TRANSPARENCY',
                ),
                const SizedBox(height: 10),
                _buildSliderCard(context, settings, notifier, transparencyPercent),

                const SizedBox(height: 20),

                // ── Section 3: Preset Buttons ────────────────────────────────
                _buildPresetsCard(settings, notifier),

                const SizedBox(height: 26),

                // ── Reset to Default Button ──────────────────────────────────
                Center(
                  child: OutlinedButton.icon(
                    onPressed: () => notifier.resetToDefault(),
                    icon: const Icon(Icons.restart_alt_rounded, size: 18, color: tabColor),
                    label: const Text(
                      'Reset to Default (70%)',
                      style: TextStyle(
                        color: tabColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: tabColor.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: tabColor.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: tabColor),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: Colors.white70,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildLivePreviewCard(ChatBubbleSettings settings) {
    final currentBackdrop = _useLightWallpaper
        ? const Color(0xFFEFE8F5)
        : const Color(0xFF0D0B14);

    final contrastReceived = settings.getTextContrast(
      isMe: false,
      backdropColor: currentBackdrop,
    );
    final contrastSent = settings.getTextContrast(
      isMe: true,
      backdropColor: currentBackdrop,
    );

    final receivedColors = settings.getBubbleGradientColors(isMe: false);
    final receivedBorder = settings.getBubbleBorderColor(isMe: false);

    final sentColors = settings.getBubbleGradientColors(isMe: true);
    final sentBorder = settings.getBubbleBorderColor(isMe: true);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF13111E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            // Decorative background patterns mimicking chat wallpaper
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  gradient: _useLightWallpaper
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFFAF7FC),
                            Color(0xFFEFE8F5),
                            Color(0xFFE5DCEF),
                          ],
                        )
                      : RadialGradient(
                          center: const Alignment(0.6, -0.4),
                          radius: 1.2,
                          colors: [
                            tabColor.withValues(alpha: 0.12),
                            const Color(0xFF1B1530).withValues(alpha: 0.8),
                            const Color(0xFF0D0B14),
                          ],
                        ),
                ),
              ),
            ),

            // Live Bubbles
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sample Received Message (Left)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                          bottomLeft: Radius.circular(4),
                        ),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 13, sigmaY: 13),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: receivedColors,
                                stops: const [0.0, 0.45, 1.0],
                              ),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(16),
                                topRight: Radius.circular(16),
                                bottomRight: Radius.circular(16),
                                bottomLeft: Radius.circular(4),
                              ),
                              border: Border.all(
                                color: receivedBorder,
                                width: 1.0,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Goddess Grace illuminates your sanctuary ✨',
                                  style: TextStyle(
                                    color: contrastReceived.primaryTextColor,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                    shadows: contrastReceived.textShadows,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: Text(
                                    '10:30 AM',
                                    style: TextStyle(
                                      color: contrastReceived.secondaryTextColor,
                                      fontSize: 10,
                                      shadows: contrastReceived.textShadows,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Sample Sent Message (Right)
                  Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(4),
                        ),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 13, sigmaY: 13),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: sentColors,
                                stops: const [0.0, 0.50, 1.0],
                              ),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(16),
                                topRight: Radius.circular(16),
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(4),
                              ),
                              border: Border.all(
                                color: sentBorder,
                                width: 1.0,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Always faithful and surrendered 🙇🏻‍♂️',
                                  style: TextStyle(
                                    color: contrastSent.primaryTextColor,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                    shadows: contrastSent.textShadows,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    const Spacer(),
                                    Text(
                                      '10:31 AM',
                                      style: TextStyle(
                                        color: contrastSent.secondaryTextColor,
                                        fontSize: 10,
                                        shadows: contrastSent.textShadows,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.done_all,
                                      size: 14,
                                      color: contrastSent.isLightBackground
                                          ? const Color(0xFF0288D1)
                                          : const Color(0xFF00E5FF),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderCard(
    BuildContext context,
    ChatBubbleSettings settings,
    ChatBubbleSettingsNotifier notifier,
    int transparencyPercent,
  ) {
    String description;
    if (transparencyPercent <= 15) {
      description = 'Solid Level: Comfortable dark obsidian & jewel tones with maximum contrast';
    } else if (transparencyPercent <= 45) {
      description = 'Tinted Glass: Rich jewel tones with visible background translucency';
    } else if (transparencyPercent <= 75) {
      description = 'Signature Glass: Frosted luxury finish with smooth contrast';
    } else {
      description = 'Ultra Glass: High translucency with background-adaptive text';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161426),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Transparency Level',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                decoration: BoxDecoration(
                  color: tabColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tabColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '$transparencyPercent%',
                  style: const TextStyle(
                    color: tabColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),

          // Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: tabColor,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              trackHeight: 5,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayColor: tabColor.withValues(alpha: 0.2),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            ),
            child: Slider(
              value: settings.transparency,
              min: 0.0,
              max: 1.0,
              onChanged: (val) => notifier.setTransparency(val),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '0% (Solid)',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
                Text(
                  '50%',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
                Text(
                  '100% (Glass)',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetsCard(
    ChatBubbleSettings settings,
    ChatBubbleSettingsNotifier notifier,
  ) {
    const presets = [
      {'label': 'Solid', 'value': 0.0, 'percent': '0%'},
      {'label': 'Tinted', 'value': 0.35, 'percent': '35%'},
      {'label': 'Default', 'value': 0.70, 'percent': '70%'},
      {'label': 'Glass', 'value': 0.90, 'percent': '90%'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161426),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Presets',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: presets.map((p) {
              final val = p['value'] as double;
              final isSelected = (settings.transparency - val).abs() < 0.04;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () => notifier.setTransparency(val),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? tabColor.withValues(alpha: 0.22)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? tabColor
                              : Colors.white.withValues(alpha: 0.12),
                          width: isSelected ? 1.2 : 0.8,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            p['label'] as String,
                            style: TextStyle(
                              color: isSelected ? tabColor : Colors.white,
                              fontSize: 11.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                          Text(
                            p['percent'] as String,
                            style: TextStyle(
                              color: isSelected ? tabColor.withValues(alpha: 0.8) : Colors.grey[500],
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
