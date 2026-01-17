import 'package:flutter/material.dart';

/// A full-screen white flash overlay that triggers on successful photo capture.
///
/// This provides immediate visual feedback that a photo was taken, following
/// the industry-standard camera UX pattern.
///
/// Usage:
/// ```dart
/// final GlobalKey<CaptureFlashOverlayState> _flashKey = GlobalKey();
///
/// CaptureFlashOverlay(
///   key: _flashKey,
///   child: YourCameraPreview(),
/// )
///
/// // After successful capture:
/// _flashKey.currentState?.flash();
/// ```
class CaptureFlashOverlay extends StatefulWidget {
  final Widget child;

  const CaptureFlashOverlay({
    super.key,
    required this.child,
  });

  @override
  State<CaptureFlashOverlay> createState() => CaptureFlashOverlayState();
}

class CaptureFlashOverlayState extends State<CaptureFlashOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  // Flash configuration
  static const Duration _flashDuration = Duration(milliseconds: 150);
  static const double _peakOpacity = 0.7;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: _flashDuration,
      vsync: this,
    );

    // Custom curve: quick rise to peak, slower fade out
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: _peakOpacity)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 33, // First third: fade in
      ),
      TweenSequenceItem(
        tween: Tween(begin: _peakOpacity, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 67, // Last two thirds: fade out
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Triggers the flash animation.
  /// Safe to call multiple times - resets if already animating.
  void flash() {
    if (!mounted) return;

    // Reset and play from beginning if already animating
    _controller.reset();
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // Flash overlay - ignores pointer events so it doesn't block interaction
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _opacityAnimation,
            builder: (context, child) {
              // Only render when actually visible (optimization)
              if (_opacityAnimation.value == 0) {
                return const SizedBox.shrink();
              }
              return Container(
                color: Colors.white.withValues(alpha: _opacityAnimation.value),
              );
            },
          ),
        ),
      ],
    );
  }
}
