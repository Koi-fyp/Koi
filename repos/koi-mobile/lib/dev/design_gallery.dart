import 'package:flutter/material.dart';

import '../theme/koi_colors.dart';
import '../theme/koi_motion.dart';
import '../theme/koi_radii.dart';
import '../theme/koi_shadows.dart';
import '../theme/koi_text.dart';
import '../theme/koi_theme.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_card.dart';
import '../widgets/neo_input.dart';

/// DEBUG-ONLY design gallery for side-by-side comparison with the web.
/// Reachable only when built in debug mode with
/// `--dart-define=KOI_DESIGN_GALLERY=true` (see main.dart).
///
/// The section titles and sample strings here are developer labels, not
/// product copy; they are never shown to users.
class DesignGallery extends StatelessWidget {
  const DesignGallery({super.key});

  static const List<(String, Color)> colors = [
    ('neo.blue', KoiColors.neoBlue),
    ('neo.yellow', KoiColors.neoYellow),
    ('neo.black', KoiColors.neoBlack),
    ('neo.white', KoiColors.neoWhite),
    ('neo.gray', KoiColors.neoGray),
    ('neo.muted', KoiColors.neoMuted),
    ('neo.coral', KoiColors.neoCoral),
    ('neo.mint', KoiColors.neoMint),
    ('neo.purple', KoiColors.neoPurple),
    ('neo.orange', KoiColors.neoOrange),
    ('background', KoiColors.background),
    ('danger', KoiColors.danger),
    ('cyan', KoiColors.cyan),
    ('inputPlaceholder', KoiColors.inputPlaceholder),
    ('focusRing', KoiColors.focusRing),
    ('--koi-brand', KoiColors.koiBrand),
    ('--koi-ai-bubble', KoiColors.koiAiBubble),
    ('--koi-dark', KoiColors.koiDark),
    ('--koi-border', KoiColors.koiBorder),
    ('--koi-muted', KoiColors.koiMuted),
    ('--koi-elevated', KoiColors.koiElevated),
  ];

  static final List<(String, List<BoxShadow>)> shadows = [
    ('neo-sm', KoiShadows.neoSm),
    ('neo-md', KoiShadows.neoMd),
    ('neo-lg', KoiShadows.neoLg),
    ('neo-xl', KoiShadows.neoXl),
    ('neo-focus', KoiShadows.neoFocus),
    ('bubbly', KoiShadows.bubbly),
    ('card', KoiShadows.card),
    ('card-lg', KoiShadows.cardLg),
    ('hard-shadow', KoiShadows.hardShadow),
    ('hard-shadow-cyan', KoiShadows.hardShadowCyan),
  ];

  static const List<(String, double)> radii = [
    ('neo', KoiRadii.neo),
    ('koi', KoiRadii.koi),
    ('xl2', KoiRadii.xl2),
    ('xl3', KoiRadii.xl3),
    ('xl4', KoiRadii.xl4),
    ('input', KoiRadii.input),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Theme(
      data: KoiTheme.light(),
      child: Scaffold(
        backgroundColor: KoiColors.background,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Design Gallery (debug)',
                  style: KoiText.neoDisplay(fontSize: 24)),
              _section('Colours'),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [for (final c in colors) _swatch(c.$1, c.$2)],
              ),
              _section('Shadows'),
              Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  for (final s in shadows)
                    _box(s.$1,
                        BoxDecoration(
                          color: KoiColors.neoWhite,
                          border: Border.all(width: 2),
                          borderRadius: KoiRadii.inputAll,
                          boxShadow: s.$2,
                        )),
                ],
              ),
              _section('Radii'),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final r in radii)
                    _box('${r.$1} ${r.$2.toStringAsFixed(0)}',
                        BoxDecoration(
                          color: KoiColors.neoYellow,
                          border: Border.all(width: 2),
                          borderRadius: BorderRadius.circular(r.$2),
                        )),
                ],
              ),
              _section('Text'),
              Text('Hero', style: KoiText.hero(width)),
              Text('neo-display 800',
                  style: KoiText.neoDisplay(fontSize: 28)),
              for (final w in const [
                FontWeight.w400,
                FontWeight.w500,
                FontWeight.w700,
                FontWeight.w800,
              ])
                Text('Bricolage Grotesque ${w.value}',
                    style: KoiText.display(fontSize: 18, fontWeight: w)),
              for (final w in const [
                FontWeight.w300,
                FontWeight.w400,
                FontWeight.w500,
                FontWeight.w700,
              ])
                Text('DM Sans ${w.value}',
                    style: KoiText.body(fontSize: 16, fontWeight: w)),
              _section('Motion'),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  const KoiFloatY(
                      spec: KoiMotion.floatSlow, child: _Chip('float-slow')),
                  const KoiFloatY(
                      spec: KoiMotion.floatMid, child: _Chip('float-mid')),
                  const KoiFloatY(
                      spec: KoiMotion.floatFast, child: _Chip('float-fast')),
                  const KoiPulseDot(child: _Chip('pulse-dot')),
                  const KoiSpin(child: _Chip('spin-slow')),
                  const KoiFadeUp(child: _Chip('fade-up')),
                  const KoiSlideRight(child: _Chip('slide-right')),
                ],
              ),
              _section('NeoButton'),
              for (final v in NeoButtonVariant.values) ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    NeoButton(
                        variant: v, onPressed: () {}, child: Text(v.name)),
                    NeoButton(
                        variant: v,
                        onPressed: null,
                        child: Text('${v.name} disabled')),
                    NeoButton(
                        variant: v,
                        loading: true,
                        onPressed: () {},
                        child: Text(v.name)),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              NeoButton(
                  fullWidth: true,
                  onPressed: () {},
                  child: const Text('fullWidth')),
              _section('NeoCard'),
              for (final v in NeoCardVariant.values) ...[
                NeoCard(
                  variant: v,
                  padding: const EdgeInsets.all(16),
                  child: Text('NeoCard ${v.name}',
                      style: KoiText.body(fontSize: 16)),
                ),
                const SizedBox(height: 20),
              ],
              _section('NeoInput'),
              const NeoInput(placeholder: 'placeholder'),
              const SizedBox(height: 16),
              const NeoInput(label: 'Label', placeholder: 'with label'),
              const SizedBox(height: 16),
              const NeoInput(
                  label: 'Label', placeholder: 'with error', error: 'Error text'),
              const SizedBox(height: 16),
              const NeoInput(
                  label: 'Textarea', placeholder: 'multiline', multiline: true),
              const SizedBox(height: 16),
              const NeoInput(placeholder: 'disabled', enabled: false),
              _section('Not built (see report)'),
              Text('BubblyButton, BubblyCard: koi-primary / koi-pastel* '
                  'colours are not defined in the web Tailwind config.',
                  style: KoiText.body(fontSize: 14)),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 32, bottom: 12),
        child: Text(title, style: KoiText.neoDisplay(fontSize: 20)),
      );

  static Widget _swatch(String name, Color color) {
    final hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(width: 1.5),
              borderRadius: KoiRadii.inputAll,
            ),
          ),
          Text(name, style: KoiText.body(fontSize: 11, fontWeight: FontWeight.w700)),
          Text(hex, style: KoiText.body(fontSize: 11)),
        ],
      ),
    );
  }

  static Widget _box(String label, Decoration decoration) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 72, height: 56, decoration: decoration),
          const SizedBox(height: 8),
          Text(label, style: KoiText.body(fontSize: 11)),
        ],
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: KoiColors.neoYellow,
          border: Border.all(width: 2),
          borderRadius: KoiRadii.inputAll,
        ),
        child: Text(label, style: KoiText.body(fontSize: 12)),
      );
}
