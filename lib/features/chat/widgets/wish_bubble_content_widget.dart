import 'package:flutter/material.dart';
import 'package:worship_chat/common/enums/message_status_enum.dart';
import 'package:worship_chat/common/utils/wish_helper.dart';

/// Clean, elegant wish bubble content widget with an ornate
/// dual-concentric royal filigree frame and 24K gold corner brackets.
class WishBubbleContentWidget extends StatelessWidget {
  final String text;
  final String date;
  final bool isMe;
  final String? senderName;
  final MessageDeliveryStatus? deliveryStatus;
  final bool isSmallScreen;
  final VoidCallback? onTap;

  const WishBubbleContentWidget({
    super.key,
    required this.text,
    required this.date,
    required this.isMe,
    this.senderName,
    this.deliveryStatus,
    this.isSmallScreen = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final wishTextStyle = WishHelper.getWishTextStyle(
      isSmallScreen: isSmallScreen,
      color: const Color(0xFFFFF9E8), // Royal Champagne Pearl
    );

    final timeTextStyle = TextStyle(
      fontSize: isSmallScreen ? 11 : 12,
      fontWeight: FontWeight.w400,
      color: const Color(0xFFFFDF73).withValues(alpha: 0.85), // Champagne gold
      height: 1.2,
    );

    final isShortSingleLine = text.length <= 26 && !text.contains('\n');

    final timeAndStatus = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(date, style: timeTextStyle),
        if (isMe && deliveryStatus != null) ...[
          const SizedBox(width: 4),
          MessageStatusIcon(
            status: deliveryStatus!,
            size: isSmallScreen ? 14 : 15,
          ),
        ],
      ],
    );

    final Widget rawContent;

    if (isShortSingleLine) {
      rawContent = Padding(
        padding: EdgeInsets.fromLTRB(
          isSmallScreen ? 12 : 14,
          isSmallScreen ? 7 : 8,
          isSmallScreen ? 10 : 12,
          isSmallScreen ? 7 : 8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                text,
                style: wishTextStyle,
              ),
            ),
            const SizedBox(width: 10),
            timeAndStatus,
          ],
        ),
      );
    } else {
      rawContent = Padding(
        padding: EdgeInsets.fromLTRB(
          isSmallScreen ? 12 : 14,
          isSmallScreen ? 8 : 10,
          isSmallScreen ? 12 : 14,
          isSmallScreen ? 6 : 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: wishTextStyle,
            ),
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.bottomRight,
              child: timeAndStatus,
            ),
          ],
        ),
      );
    }

    final innerRadius = WishHelper.getInnerBubbleRadius(
      isMe: isMe,
      isSmallScreen: isSmallScreen,
    );

    // Embossed minted coin-edge frame with corner jewel studs
    final Widget framedContent = Padding(
      padding: const EdgeInsets.all(3.5),
      child: CustomPaint(
        painter: _RoyalMintedReliefBorderPainter(
          borderRadius: innerRadius,
          highlightColor: const Color(0x38FFDF73), // Subtle champagne gold hairline
          shadowColor: const Color(0x38000000),    // Soft depth shadow
          jewelColor: const Color(0xFFFFDF73),     // Champagne gold diamond stud
        ),
        child: rawContent,
      ),
    );

    if (onTap == null) {
      return framedContent;
    }

    return GestureDetector(
      onTap: onTap,
      child: framedContent,
    );
  }
}

/// Custom painter that draws an embossed minted coin-edge dual-filament frame
/// with four delicate jewel-faceted diamond pips on the corner arcs.
class _RoyalMintedReliefBorderPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final Color highlightColor;
  final Color shadowColor;
  final Color jewelColor;

  _RoyalMintedReliefBorderPainter({
    required this.borderRadius,
    required this.highlightColor,
    required this.shadowColor,
    required this.jewelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = borderRadius.toRRect(rect);

    // 1. Draw outer beveled depth hairline
    final shadowPaint = Paint()
      ..color = shadowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75;
    canvas.drawRRect(rrect, shadowPaint);

    // 2. Draw inner champagne highlight hairline
    if (rrect.width > 2.0 && rrect.height > 2.0) {
      final highlightPaint = Paint()
        ..color = highlightColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.85;
      canvas.drawRRect(rrect.deflate(0.9), highlightPaint);
    }

    // 3. Draw four delicate micro-diamond corner studs (✦)
    final jewelFill = Paint()
      ..color = jewelColor
      ..style = PaintingStyle.fill;

    final jewelHighlight = Paint()
      ..color = const Color(0xFFFFFDE7) // Radiant ivory diamond center
      ..style = PaintingStyle.fill;

    void drawCornerDiamond(double cx, double cy) {
      const radius = 2.4;
      final path = Path()
        ..moveTo(cx, cy - radius)
        ..lineTo(cx + radius, cy)
        ..lineTo(cx, cy + radius)
        ..lineTo(cx - radius, cy)
        ..close();
      canvas.drawPath(path, jewelFill);
      canvas.drawCircle(Offset(cx, cy), 0.75, jewelHighlight);
    }

    // Positions for 4 corner diamonds along the corner curves
    // Top-Left
    final tlX = rect.left + rrect.tlRadiusX * (1 - 0.707);
    final tlY = rect.top + rrect.tlRadiusY * (1 - 0.707);
    drawCornerDiamond(tlX + 1.2, tlY + 1.2);

    // Top-Right
    final trX = rect.right - rrect.trRadiusX * (1 - 0.707);
    final trY = rect.top + rrect.trRadiusY * (1 - 0.707);
    drawCornerDiamond(trX - 1.2, trY + 1.2);

    // Bottom-Left
    final blX = rect.left + rrect.blRadiusX * (1 - 0.707);
    final blY = rect.bottom - rrect.blRadiusY * (1 - 0.707);
    drawCornerDiamond(blX + 1.2, blY - 1.2);

    // Bottom-Right
    final brX = rect.right - rrect.brRadiusX * (1 - 0.707);
    final brY = rect.bottom - rrect.brRadiusY * (1 - 0.707);
    drawCornerDiamond(brX - 1.2, brY - 1.2);
  }

  @override
  bool shouldRepaint(covariant _RoyalMintedReliefBorderPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
        oldDelegate.highlightColor != highlightColor ||
        oldDelegate.shadowColor != shadowColor ||
        oldDelegate.jewelColor != jewelColor;
  }
}
