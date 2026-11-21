import 'package:flutter/material.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';

/// Pointer controls complement the swipe gesture used on phones and tablets.
class GalleryNavigationControls extends StatelessWidget {
  final PageController controller;
  final int currentIndex;
  final int imageCount;

  const GalleryNavigationControls({
    super.key,
    required this.controller,
    required this.currentIndex,
    required this.imageCount,
  });

  @override
  Widget build(BuildContext context) {
    if (!AppCapabilities.current.isDesktop || imageCount <= 1) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton.filledTonal(
              tooltip: 'Previous photo',
              onPressed: currentIndex > 0
                  ? () => controller.previousPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                    )
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton.filledTonal(
              tooltip: 'Next photo',
              onPressed: currentIndex < imageCount - 1
                  ? () => controller.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                    )
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
