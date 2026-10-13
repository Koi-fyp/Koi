import 'package:flutter/material.dart';

import '../onboarding/step_layout.dart' show bodyText;
import '../theme/koi_colors.dart';

/// The `<footer>` shared by src/app/page.tsx, about/page.tsx and
/// how-it-works/page.tsx at phone width (`flex-col items-center gap-6`).
/// Only the three middle links differ per page.
class KoiFooter extends StatelessWidget {
  const KoiFooter({super.key, required this.links});

  /// (label, onTap) for the `text-sm font-semibold text-black/60` links.
  final List<(String, VoidCallback)> links;

  static const Color _gray400 = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) {
    Widget link(String label, VoidCallback onTap) => GestureDetector(
      key: Key('footer-$label'),
      onTap: onTap,
      child: Text(
        label,
        style: bodyText(
          14,
          weight: FontWeight.w600,
          color: const Color(0x99000000),
          height: 20 / 14,
        ), // black/60
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40), // px-6 pb-10
      child: Container(
        // .koi-footer-wrapper: border 3px; radius 8px; box-shadow 4px 4px
        // #000; background linear-gradient(#2D63EB30) under
        // linear-gradient(90deg, #f1f1f1f5 19%, #0000)
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0x302D63EB),
          border: Border.all(width: 3),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(offset: Offset(4, 4))],
        ),
        child: Container(
          padding: const EdgeInsets.all(48), // padding: 3rem
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              // CSS interpolates in premultiplied space; ending on a
              // transparent #f1f1f1 matches that.
              colors: [Color(0xF5F1F1F1), Color(0xF5F1F1F1), Color(0x00F1F1F1)],
              stops: [0, 0.19, 1],
            ),
          ),
          child: Column(
            children: [
              // flex-col items-center gap-6
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D63EB),
                      border: Border.all(width: 1.5),
                      borderRadius: BorderRadius.circular(8), // rounded-lg
                    ),
                    child: Text(
                      'K',
                      style: bodyText(
                        14,
                        weight: FontWeight.w700,
                        color: KoiColors.neoWhite,
                        height: 20 / 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'KOI',
                    style: bodyText(
                      14,
                      weight: FontWeight.w700,
                      height: 20 / 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < links.length; i++) ...[
                    if (i > 0) const SizedBox(width: 24), // gap-6
                    link(links[i].$1, links[i].$2),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Private · No account needed · Always here for you',
                style: bodyText(
                  12,
                  weight: FontWeight.w500,
                  color: _gray400,
                  height: 16 / 12,
                ),
              ),
              const SizedBox(height: 24), // mt-6
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 24), // pt-6
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(width: 2, color: Color(0x1A000000)),
                  ), // black/10
                ),
                child: Column(
                  children: [
                    Text(
                      '© 2025 KOI · All rights reserved',
                      style: bodyText(
                        12,
                        weight: FontWeight.w600,
                        color: const Color(0x66000000),
                        height: 16 / 12,
                      ),
                    ),
                    const SizedBox(height: 8), // gap-2
                    Text(
                      'Built with care in Pakistan 🇵🇰',
                      style: bodyText(
                        12,
                        color: const Color(0x4D000000),
                        height: 16 / 12,
                      ),
                    ), // black/30
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
