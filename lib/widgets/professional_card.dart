import 'package:flutter/material.dart';

class ProfessionalCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? backgroundColor;

  const ProfessionalCard({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 12.0,
    this.backgroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? const Color(0xFF1E293B), // Soft Slate Blue
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: const Color(0xFF334155), width: 1.5), // Slate border
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF06B6D4).withOpacity(0.08), // Subtle cyan glow
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: child,
    );
  }
}
