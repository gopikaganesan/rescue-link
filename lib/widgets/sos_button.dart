import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/providers/app_settings_provider.dart';
import 'dart:math' as math;

class SOSButton extends StatefulWidget {
  final Future<void> Function() onPressed;
  final bool isLoading;
  final bool enableHaptics;
  final bool isActive;
  final String? activeLabel;
  final String? activeSubLabel;

  const SOSButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.enableHaptics = true,
    this.isActive = false,
    this.activeLabel,
    this.activeSubLabel,
  });

  @override
  State<SOSButton> createState() => _SOSButtonState();
}

class _SOSButtonState extends State<SOSButton>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handlePress() async {
    if (widget.enableHaptics) {
      try {
        await HapticFeedback.heavyImpact();
        await HapticFeedback.selectionClick();
      } catch (e) {
        // Silently fail if haptic not available
      }
    }

    setState(() => _isPressed = true);
    await widget.onPressed();

    // Visual feedback - reset after animation
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() => _isPressed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<AppSettingsProvider>();
    final buttonLabel = widget.isActive
        ? (widget.activeLabel ?? settings.t('button_cancel_sos'))
        : settings.t('sos_button_label');
    final buttonSublabel = widget.isActive
        ? (widget.activeSubLabel ?? settings.t('sos_button_cancel_hint'))
        : settings.t('sos_button_tap');
    final gradientColors = widget.isActive
        ? [Colors.red.shade700, Colors.red.shade900]
        : [Colors.red.shade500, Colors.red.shade700];
    final isTapEnabled = widget.isActive || !widget.isLoading;
    return Semantics(
      button: true,
      enabled: isTapEnabled,
      label: settings.t('sos_button_accessibility_label'),
      hint: settings.t('sos_button_accessibility_hint'),
      child: GestureDetector(
        onTap: isTapEnabled ? _handlePress : null,
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                // Outer pulsing rings
                if (!widget.isLoading && !_isPressed)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: PulseRingPainter(
                        progress: _pulseAnimation.value,
                        color: Colors.red.shade600,
                      ),
                    ),
                  ),
                // Main button
                Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.6),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isTapEnabled ? _handlePress : null,
                      splashColor: Colors.red.shade900,
                      customBorder: const CircleBorder(),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: _isPressed ? 140 : 150,
                        width: _isPressed ? 140 : 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: gradientColors,
                          ),
                          border: Border.all(
                            color: Colors.red.shade900,
                            width: 3,
                          ),
                          boxShadow: [
                            if (!_isPressed)
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.4),
                                blurRadius: 15,
                                spreadRadius: 3,
                              ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Loading indicator
                            if (widget.isLoading)
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                      Colors.white.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ),
                              ),
                            // SOS Text
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  buttonLabel,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 2,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  buttonSublabel,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Colors.white
                                            .withValues(alpha: 0.9),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class PulseRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  PulseRingPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    // Draw multiple rings with decreasing opacity
    for (int i = 3; i >= 1; i--) {
      final ringRadius = radius + (radius * progress * i);
      final opacity = (1 - progress) * (1 / i);

      final paint = Paint()
        ..color = color.withValues(alpha: opacity * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, ringRadius, paint);
    }
  }

  @override
  bool shouldRepaint(PulseRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
