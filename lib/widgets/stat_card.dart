import 'package:flutter/material.dart';
import '../theme/ui_tokens.dart';

class StatCard extends StatefulWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  State<StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<StatCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.color;
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 480;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: (_hovered || _pressed) ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accent.withValues(
                  alpha: (_hovered || _pressed) ? 0.25 : 0.15,
                ),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withValues(
                    alpha: (_hovered || _pressed) ? 0.14 : 0.06,
                  ),
                  blurRadius: (_hovered || _pressed) ? 20 : 10,
                  offset: Offset(0, (_hovered || _pressed) ? 10 : 4),
                ),
              ],
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: isMobile ? 0.08 : 0.10),
                  accent.withValues(alpha: isMobile ? 0.05 : 0.06),
                ],
                stops: const [0.15, 0.95],
              ),
            ),
            child: Stack(
              children: [
                // Top-right icon tile
                Positioned(
                  top: isMobile ? 10 : 12,
                  right: isMobile ? 10 : 12,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    width: isMobile ? 32 : 36,
                    height: isMobile ? 32 : 36,
                    decoration: BoxDecoration(
                      color: (_hovered || _pressed)
                          ? accent
                          : accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(UITokens.radius),
                      border: Border.all(
                        color: (_hovered || _pressed)
                            ? accent.withValues(alpha: 0.40)
                            : accent.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      size: isMobile ? 16 : 18,
                      color: (_hovered || _pressed)
                          ? Colors.white
                          : Theme.of(context).textTheme.bodyMedium?.color
                                ?.withValues(alpha: 0.8),
                    ),
                  ),
                ),

                // Content
                Padding(
                  padding: EdgeInsets.all(isMobile ? 14 : 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontSize: isMobile ? 12 : null,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color
                                        ?.withValues(alpha: 0.9),
                                  ),
                            ),
                            SizedBox(height: isMobile ? 6 : 8),
                            Text(
                              widget.value,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontSize: isMobile ? 20 : null,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
