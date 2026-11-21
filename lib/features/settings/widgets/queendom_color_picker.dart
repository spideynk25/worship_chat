import 'package:flutter/material.dart';
import 'package:worship_chat/colors.dart';

/// Interactive, full-featured Queendom Color Picker with 2D Saturation/Value area,
/// Hue slider bar, Hex code input, and royal presets.
class QueendomColorPicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;

  const QueendomColorPicker({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
  });

  /// Static helper to display the color picker in a sleek bottom sheet or dialog
  static Future<Color?> showColorPickerDialog(
    BuildContext context, {
    required Color currentColor,
    String title = 'Choose Accent Color',
  }) {
    Color selected = currentColor;
    return showDialog<Color>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161426),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          title: Row(
            children: [
              const Icon(Icons.colorize_rounded, color: tabColor, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: QueendomColorPicker(
                initialColor: currentColor,
                onColorChanged: (c) => selected = c,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: tabColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Apply Color', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  State<QueendomColorPicker> createState() => _QueendomColorPickerState();
}

class _QueendomColorPickerState extends State<QueendomColorPicker> {
  late double _hue; // 0.0 - 360.0
  late double _saturation; // 0.0 - 1.0
  late double _value; // 0.0 - 1.0
  late TextEditingController _hexController;

  static const List<Color> _royalPresets = [
    Color(0xFFFFD700), // Imperial Gold
    Color(0xFFCFAB09), // Golden Blossom
    Color(0xFFFF6347), // Coral Queen
    Color(0xFFE74C3C), // Crimson Supreme
    Color(0xFFE91E63), // Rose Magenta
    Color(0xFFFF69B4), // Hot Pink
    Color(0xFFBA68C8), // Orchid Princess
    Color(0xFF8E44AD), // Royal Violet
    Color(0xFF9B59B6), // Goddess Purple
    Color(0xFF4A3570), // Dark Angel Indigo
    Color(0xFF4A90E2), // Sapphire Core
    Color(0xFF00E5FF), // Cyan Aura
    Color(0xFF1ABC9C), // Jade Enchantress
    Color(0xFF2ECC71), // Emerald Witch
    Color(0xFFFF9800), // Sunset Amber
    Color(0xFFCE93D8), // Light Lavender
  ];

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initialColor);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = hsv.value;
    _hexController = TextEditingController(text: _colorToHex(widget.initialColor));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _currentColor {
    return HSVColor.fromAHSV(1.0, _hue, _saturation, _value).toColor();
  }

  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  void _updateFromHSV({double? hue, double? saturation, double? value}) {
    setState(() {
      if (hue != null) _hue = hue.clamp(0.0, 360.0);
      if (saturation != null) _saturation = saturation.clamp(0.0, 1.0);
      if (value != null) _value = value.clamp(0.0, 1.0);
      final c = _currentColor;
      _hexController.text = _colorToHex(c);
      widget.onColorChanged(c);
    });
  }

  void _updateFromHex(String rawText) {
    var text = rawText.trim().replaceAll('#', '');
    if (text.length == 6) {
      final val = int.tryParse('FF$text', radix: 16);
      if (val != null) {
        final c = Color(val);
        final hsv = HSVColor.fromColor(c);
        setState(() {
          _hue = hsv.hue;
          _saturation = hsv.saturation;
          _value = hsv.value;
          widget.onColorChanged(c);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = _currentColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 1. Saturation & Value 2D Box ────────────────────────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final boxWidth = constraints.maxWidth;
              const boxHeight = 150.0;

              return GestureDetector(
                onPanDown: (details) => _handleSatValTouch(details.localPosition, boxWidth, boxHeight),
                onPanUpdate: (details) => _handleSatValTouch(details.localPosition, boxWidth, boxHeight),
                child: Container(
                  width: boxWidth,
                  height: boxHeight,
                  decoration: BoxDecoration(
                    color: HSVColor.fromAHSV(1.0, _hue, 1.0, 1.0).toColor(),
                  ),
                  child: Stack(
                    children: [
                      // White gradient (horizontal: Saturation)
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Colors.white, Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                      // Black gradient (vertical: Value / Brightness)
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black],
                            ),
                          ),
                        ),
                      ),
                      // Thumb indicator
                      Positioned(
                        left: (_saturation * boxWidth - 10).clamp(0.0, boxWidth - 20),
                        top: ((1.0 - _value) * boxHeight - 10).clamp(0.0, boxHeight - 20),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: currentColor,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 14),

        // ── 2. Hue Slider Bar ────────────────────────────────────────────────
        const Text(
          'HUE SPECTRUM',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              const barHeight = 22.0;

              return GestureDetector(
                onPanDown: (details) => _handleHueTouch(details.localPosition, barWidth),
                onPanUpdate: (details) => _handleHueTouch(details.localPosition, barWidth),
                child: Container(
                  width: barWidth,
                  height: barHeight,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFFF0000), // Red
                        Color(0xFFFFFF00), // Yellow
                        Color(0xFF00FF00), // Green
                        Color(0xFF00FFFF), // Cyan
                        Color(0xFF0000FF), // Blue
                        Color(0xFFFF00FF), // Magenta
                        Color(0xFFFF0000), // Red
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: ((_hue / 360.0) * barWidth - 8).clamp(0.0, barWidth - 16),
                        top: 1,
                        bottom: 1,
                        child: Container(
                          width: 16,
                          decoration: BoxDecoration(
                            color: HSVColor.fromAHSV(1.0, _hue, 1.0, 1.0).toColor(),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 14),

        // ── 3. Color Preview & Hex Code Field ────────────────────────────────
        Row(
          children: [
            // Preview Circle with Glow
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: currentColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white38, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: currentColor.withValues(alpha: 0.5),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _hexController,
                onChanged: _updateFromHex,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                ),
                decoration: InputDecoration(
                  labelText: 'HEX CODE',
                  labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                  prefixIcon: const Icon(Icons.tag_rounded, color: tabColor, size: 18),
                  filled: true,
                  fillColor: const Color(0xFF0F0E17),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: tabColor),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // ── 4. Quick Royal Palette Swatches ──────────────────────────────────
        const Text(
          'ROYAL PRESETS',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _royalPresets.map((preset) {
            final isSelected = currentColor.toARGB32() == preset.toARGB32();
            return GestureDetector(
              onTap: () {
                final hsv = HSVColor.fromColor(preset);
                _updateFromHSV(hue: hsv.hue, saturation: hsv.saturation, value: hsv.value);
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: preset,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.white12,
                    width: isSelected ? 2.5 : 1.0,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: preset.withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _handleSatValTouch(Offset pos, double width, double height) {
    final sat = (pos.dx / width).clamp(0.0, 1.0);
    final val = (1.0 - (pos.dy / height)).clamp(0.0, 1.0);
    _updateFromHSV(saturation: sat, value: val);
  }

  void _handleHueTouch(Offset pos, double width) {
    final h = ((pos.dx / width) * 360.0).clamp(0.0, 360.0);
    _updateFromHSV(hue: h);
  }
}

