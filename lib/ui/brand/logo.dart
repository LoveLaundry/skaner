import 'package:flutter/material.dart';

import '../../ui/theme.dart';

/// The brand mark, drawn rather than shipped as an asset so it re-tints with the
/// active theme instead of carrying a hard-coded background.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40, this.showWordmark = true});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c.brandHover, c.brand],
            ),
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.local_laundry_service_outlined,
            size: size * 0.58,
            color: Colors.white,
          ),
        ),
        if (showWordmark) ...[
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Love Laundry',
                style: context.texts.titleMedium?.copyWith(
                  color: c.fg,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                'Operations',
                style: context.texts.labelSmall?.copyWith(
                  color: c.fgFaint,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
