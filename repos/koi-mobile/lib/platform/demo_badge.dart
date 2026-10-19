import 'package:flutter/material.dart';

import '../theme/koi_colors.dart';
import '../theme/koi_radii.dart';
import '../theme/koi_shadows.dart';
import '../theme/koi_text.dart';

/// "Demo data" marker for every screen whose content comes from a mock
/// adapter (KOI_MOCKS=true). Built from the KOI tokens only: a yellow pill
/// with the Neo border and a small hard shadow.
class DemoDataBadge extends StatelessWidget {
  const DemoDataBadge({super.key});

  static const String label = 'Demo data';

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Demo data. Not real account data.',
    excludeSemantics: true,
    child: Container(
      key: const Key('demo-data-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: KoiColors.neoYellow,
        border: Border.all(width: 2),
        borderRadius: KoiRadii.pillAll,
        boxShadow: KoiShadows.neoSm,
      ),
      child: Text(
        label,
        style: KoiText.body(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: KoiColors.neoBlack,
          letterSpacing: 0,
        ),
      ),
    ),
  );
}
