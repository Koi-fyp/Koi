import 'package:flutter/material.dart';

import '../theme/koi_colors.dart';
import '../theme/koi_motion.dart';
import '../theme/koi_shadows.dart';
import '../theme/koi_text.dart';

/// Loading splash. Every value is from the `loading || !user` branch of
/// repos/koi-backend/nextjs_app/src/app/(authenticated)/layout.tsx.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const double size = 44; // width/height: 44px
  static const double radius = 10; // borderRadius: 10px
  static const double borderWidth = 2.5; // border: 2.5px solid #000
  static const double fontSize = 1.2 * 16; // fontSize: 1.2rem
  static const KoiAnimationSpec fadeUp = KoiAnimationSpec(
    duration: Duration(milliseconds: 400),
  ); // fadeUp 0.4s ease both

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: KoiColors.background, // background: #ffe5d9
      child: Center(
        child: KoiFadeUp(
          spec: fadeUp,
          child: Container(
            key: const Key('splash-logo'),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: KoiColors.neoBlue, // var(--neo-blue)
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: KoiColors.neoBlack, width: borderWidth),
              boxShadow: KoiShadows.neoMd, // boxShadow: 4px 4px 0 0 #000
            ),
            child: Text(
              'K',
              style: KoiText.display(
                fontWeight: FontWeight.w800,
                fontSize: fontSize,
                color: KoiColors.neoWhite,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
