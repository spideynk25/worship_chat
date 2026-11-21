import 'package:flutter/material.dart';

enum QueendomType { pooja, rashmika }

class QueendomBadgeHelper {
  static const String poojaBadgeAsset = 'assets/images/queen_pooja_badge.jpg';
  static const String rashmikaBadgeAsset = 'assets/images/queen_rashmika_badge.jpg';

  static QueendomType? detectQueendom({
    String? queendom,
    String? name,
    String? title,
    String? type,
  }) {
    final lowerQueendom = queendom?.toLowerCase() ?? '';
    final lowerName = name?.toLowerCase() ?? '';
    final lowerTitle = title?.toLowerCase() ?? '';
    final lowerType = type?.toLowerCase() ?? '';

    final isPooja = lowerQueendom.contains('pooja') ||
        lowerName.contains('pooja') ||
        lowerTitle.contains('pooja') ||
        lowerType.contains('pooja');

    if (isPooja) return QueendomType.pooja;

    final isRashmika = lowerQueendom.contains('rashmika') ||
        lowerName.contains('rashmika') ||
        lowerTitle.contains('rashmika') ||
        lowerType.contains('rashmika');

    if (isRashmika) return QueendomType.rashmika;

    return null;
  }

  static String? getBadgeAsset({
    String? queendom,
    String? name,
    String? title,
    String? type,
  }) {
    final detected = detectQueendom(
      queendom: queendom,
      name: name,
      title: title,
      type: type,
    );
    if (detected == QueendomType.pooja) return poojaBadgeAsset;
    if (detected == QueendomType.rashmika) return rashmikaBadgeAsset;
    return null;
  }

  static Color getAccentColor(QueendomType type) {
    switch (type) {
      case QueendomType.pooja:
        return const Color(0xFFFFD700);
      case QueendomType.rashmika:
        return const Color(0xFFFF4081);
    }
  }
}

/// A circular royal photo badge displaying Queen Pooja or Queen Rashmika.
class QueendomBadgeWidget extends StatelessWidget {
  final QueendomType? queendomType;
  final String? queendom;
  final String? name;
  final String? title;
  final String? type;
  final double size;
  final Color? borderColor;
  final double? borderWidth;
  final bool showGlow;
  final Alignment imageAlignment;

  const QueendomBadgeWidget({
    super.key,
    this.queendomType,
    this.queendom,
    this.name,
    this.title,
    this.type,
    this.size = 24.0,
    this.borderColor,
    this.borderWidth,
    this.showGlow = true,
    this.imageAlignment = const Alignment(0, -0.35),
  });

  @override
  Widget build(BuildContext context) {
    final detected = queendomType ??
        QueendomBadgeHelper.detectQueendom(
          queendom: queendom,
          name: name,
          title: title,
          type: type,
        );

    if (detected == null) return const SizedBox.shrink();

    final asset = detected == QueendomType.pooja
        ? QueendomBadgeHelper.poojaBadgeAsset
        : QueendomBadgeHelper.rashmikaBadgeAsset;
    final effectiveBorderColor =
        borderColor ?? QueendomBadgeHelper.getAccentColor(detected);
    final effectiveBorderWidth = borderWidth ?? (size >= 30 ? 2.0 : 1.4);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF14131E),
        border: Border.all(
          color: effectiveBorderColor,
          width: effectiveBorderWidth,
        ),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: effectiveBorderColor.withValues(alpha: 0.5),
                  blurRadius: size * 0.35,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: ClipOval(
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          alignment: imageAlignment,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

