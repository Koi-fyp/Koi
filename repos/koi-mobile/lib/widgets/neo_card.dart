import 'package:flutter/widgets.dart';

import '../theme/koi_colors.dart';
import '../theme/koi_radii.dart';
import '../theme/koi_shadows.dart';

/// Mirrors src/components/ui/NeoCard.tsx: variant 'default' | 'yellow' |
/// 'elevated'.
enum NeoCardVariant { normal, yellow, elevated }

/// Mirrors repos/koi-backend/nextjs_app/src/components/ui/NeoCard.tsx and the
/// `.neo-card`, `.neo-card--yellow`, `.neo-card--elevated` classes in
/// src/app/globals.css. All variants: border 2.5px solid #000,
/// border-radius 1.25rem (20px).
///
/// The web card has no padding of its own (callers add it via className), so
/// [padding] defaults to zero.
class NeoCard extends StatelessWidget {
  const NeoCard({
    super.key,
    required this.child,
    this.variant = NeoCardVariant.normal,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;

  /// `normal` is the web 'default' variant (`default` is reserved in Dart).
  final NeoCardVariant variant;
  final EdgeInsetsGeometry padding;

  static const double borderWidth = 2.5;

  @override
  Widget build(BuildContext context) {
    final (Color background, List<BoxShadow> shadow) = switch (variant) {
      // .neo-card: #fff, box-shadow var(--shadow-lg) = 6px 6px 0 0 #000
      NeoCardVariant.normal => (KoiColors.neoWhite, KoiShadows.hard(6)),
      // .neo-card--yellow: var(--neo-yellow), 5px 5px 0 0 #000
      NeoCardVariant.yellow => (KoiColors.neoYellow, KoiShadows.hard(5)),
      // .neo-card--elevated: #fff, 8px 8px 0 0 #000
      NeoCardVariant.elevated => (KoiColors.neoWhite, KoiShadows.hard(8)),
    };

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(width: borderWidth),
        borderRadius: KoiRadii.neoAll,
        boxShadow: shadow,
      ),
      child: child,
    );
  }
}
