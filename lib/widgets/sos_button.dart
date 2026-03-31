import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SOSButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isLoading;

  const SOSButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  State<SOSButton> createState() => _SOSButtonState();
}

class _SOSButtonState extends State<SOSButton> {
  bool _isPressed = false;

  void _handlePress() async {
    // Haptic feedback - strong vibration
    try {
      HapticFeedback.heavyImpact();
    } catch (e) {
      // Silently fail if haptic not available
    }

    setState(() => _isPressed = true);
    widget.onPressed();

    // Visual feedback - reset after animation
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() => _isPressed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.isLoading ? null : _handlePress,
          splashColor: Colors.red.shade900,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: _isPressed ? 140 : 150,
            width: _isPressed ? 140 : 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.shade600,
              border: Border.all(
                color: Colors.red.shade900,
                width: 3,
              ),
              boxShadow: [
                if (!_isPressed)
                  BoxShadow(
                    color: Colors.red.withOpacity(0.4),
                    blurRadius: 15,
                    spreadRadius: 3,
                  ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Pulsing ring effect (when not pressed)
                if (!widget.isLoading && !_isPressed)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.red.shade400.withOpacity(0.6),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                // Center content
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.isLoading)
                      const SizedBox(
                        height: 35,
                        width: 35,
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 3,
                        ),
                      )
                    else ...[
                      Icon(
                        Icons.emergency,
                        color: Colors.white,
                        size: _isPressed ? 50 : 60,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'SOS',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: _isPressed ? 18 : 20,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
