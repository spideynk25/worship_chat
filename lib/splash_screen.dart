import 'package:flutter/material.dart';
import 'package:worship_chat/colors.dart';

/// A modern, tier-1 splash screen for Worship Chat with coordinated entrance animations,
/// ambient breathing glow, and platform-aligned branding.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _pulseController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _textOpacity;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _glowScale;
  late final Animation<double> _glowOpacity;
  late final Animation<double> _bottomOpacity;

  @override
  void initState() {
    super.initState();

    // Coordinated entrance: completes smoothly within 700ms
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    // Subtle breathing ambient pulse (non-blocking)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
      ),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.25, 0.85, curve: Curves.easeOut),
      ),
    );

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.25, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _bottomOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
      ),
    );

    _glowScale = Tween<double>(begin: 0.95, end: 1.06).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _glowOpacity = Tween<double>(begin: 0.35, end: 0.65).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background Ambient Radial Gradient ──
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 1.0,
                  colors: [
                    tabColor.withValues(alpha: 0.16),
                    accentOrange.withValues(alpha: 0.06),
                    backgroundColor,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // ── Center Content: App Emblem, Title & Tagline ──
          Center(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated Logo with Breathing Ambient Glow
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        _entranceController,
                        _pulseController,
                      ]),
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _logoScale.value,
                          child: Opacity(
                            opacity: _logoOpacity.value,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Ambient soft glow ring
                                Transform.scale(
                                  scale: _glowScale.value,
                                  child: Container(
                                    width: 130,
                                    height: 130,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: tabColor.withValues(
                                            alpha: _glowOpacity.value * 0.45,
                                          ),
                                          blurRadius: 48,
                                          spreadRadius: 8,
                                        ),
                                        BoxShadow(
                                          color: accentOrange.withValues(
                                            alpha: _glowOpacity.value * 0.25,
                                          ),
                                          blurRadius: 64,
                                          spreadRadius: 16,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Squircle Icon Container
                                Container(
                                  width: 112,
                                  height: 112,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(26),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        tabColor.withValues(alpha: 0.3),
                                        Colors.white.withValues(alpha: 0.08),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.22),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.5),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.asset(
                                    'assets/app icons/app_icon.jpg',
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.high,
                                    errorBuilder: (_, __, ___) => Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [tabColor, accentOrange],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.chat_bubble_rounded,
                                          color: Colors.white,
                                          size: 52,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 32),

                    // App Title & Tagline with Smooth Slide & Fade
                    SlideTransition(
                      position: _textSlide,
                      child: FadeTransition(
                        opacity: _textOpacity,
                        child: Column(
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [
                                  Colors.white,
                                  Color(0xFFFFF0F5),
                                  Color(0xFFFFD4E2),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ).createShader(bounds),
                              child: const Text(
                                'Worship Chat',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom Branding & Discreet Activity Indicator ──
          Positioned(
            left: 0,
            right: 0,
            bottom: size.height > 600 ? 44 : 24,
            child: FadeTransition(
              opacity: _bottomOpacity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Subtle smooth shimmer loading line
                  const _SleekBootLoader(),
                  const SizedBox(height: 20),
                  Text(
                    'from',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.32),
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.favorite_rounded,
                        size: 13,
                        color: tabColor.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'WORSHIP',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact, elegant loading indicator for splash initialization.
class _SleekBootLoader extends StatefulWidget {
  const _SleekBootLoader();

  @override
  State<_SleekBootLoader> createState() => _SleekBootLoaderState();
}

class _SleekBootLoaderState extends State<_SleekBootLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Container(
          width: 48,
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Align(
            alignment: Alignment(-1.5 + (_ctrl.value * 3.0), 0),
            child: Container(
              width: 24,
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(
                  colors: [tabColor, accentOrange],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
