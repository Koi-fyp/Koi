import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../onboarding/steps/ai_disclosure_step.dart' show UrlOpener;
import '../theme/koi_text.dart';
import '../widgets/neo_button.dart';
import 'safety_contract.dart';
import 'safety_controller.dart';

Future<void> _launch(Uri uri) async {
  // As in ai_disclosure_step.dart: launchUrl directly, no canLaunchUrl.
  await launchUrl(uri);
}

/// UX Flow 4 crisis safety screen. Layout, colours and text mirror Web's
/// CrisisHandoffDialog.tsx + CompanionScene.module.css `.crisis*`
/// (origin/feat/avatar-webview-host); the content comes from the contract's
/// `intervention_content` (§4), not Web's internal display shape.
///
/// It cannot be dismissed: back is blocked and there is nothing to tap
/// outside. The only ways out are the three path buttons.
///
/// Mobile-only additions (not on Web): the "General support message" label
/// for fallback content and the call button. Like Web, neither the risk
/// category nor the crisis score is shown; the category is only used to
/// decide when to open and which content is allowed (CrisisView).
class CrisisScreen extends StatefulWidget {
  const CrisisScreen({
    super.key,
    required this.view,
    required this.onChoose,
    this.openUrl = _launch,
  });

  final CrisisView view;
  final ValueChanged<CrisisPath> onChoose;

  /// Opens the `tel:` link. Injectable for tests.
  final UrlOpener openUrl;

  // Web text (CrisisHandoffDialog.tsx).
  static const String title = 'Let’s check what support you need';
  static const String description =
      'KOI has paused this conversation to check in with you. Choose the '
      'response that best fits.';
  static const String limitedInformation = 'Limited information';
  static const String unavailable =
      'Support details are unavailable in this chat response.';
  static const Map<CrisisPath, String> pathLabels = {
    CrisisPath.reachedOut: 'I reached out for support',
    CrisisPath.saidButDidNot: 'I said that, but did not reach out',
    CrisisPath.misunderstanding: 'There was a misunderstanding',
  };

  // Mobile-only text (user decision 2026-10-17).
  static const String fallbackLabel = 'General support message';
  static String callLabel(String number) => 'Call $number';

  /// `tel:` URI with only the dialable characters of [number].
  static Uri telUri(String number) =>
      Uri(scheme: 'tel', path: number.replaceAll(RegExp(r'[^0-9+]'), ''));

  // CompanionScene.module.css literals.
  static const Color backdrop = Color(0xD9221C1B); // #221c1bd9
  static const Color dialogBg = Color(0xFFFFFAF6); // #fffaf6
  static const Color textColor = Color(0xFF2B2421); // #2b2421
  static const Color contentBg = Color(0xFFF2E7DC); // #f2e7dc
  static const Color sourceColor = Color(0xFF61564E); // #61564e
  static const Color choiceBorder = Color(0xFF816E61); // #816e61

  @override
  State<CrisisScreen> createState() => _CrisisScreenState();
}

class _CrisisScreenState extends State<CrisisScreen> {
  bool _chosen = false;

  void _choose(CrisisPath path) {
    // Web `choiceMade`: one path per opening.
    if (_chosen) return;
    _chosen = true;
    widget.onChoose(path);
  }

  TextStyle _text(double size, {Color? color, double? height}) => KoiText.body(
    fontSize: size,
    color: color ?? CrisisScreen.textColor,
    height: height,
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // padding: clamp(20px, 5vw, 32px); h2 font-size: clamp(21px, 5vw, 28px)
    final pad = (width * 0.05).clamp(20.0, 32.0);
    final titleSize = (width * 0.05).clamp(21.0, 28.0);
    return PopScope<Object?>(
      canPop: false,
      child: Material(
        color: CrisisScreen.backdrop,
        child: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: CrisisScreen.dialogBg,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                  boxShadow: [
                    // 0 18px 60px #0005
                    BoxShadow(
                      color: Color(0x55000000),
                      offset: Offset(0, 18),
                      blurRadius: 60,
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(pad),
                  child: Semantics(
                    scopesRoute: true,
                    namesRoute: true,
                    explicitChildNodes: true,
                    label: CrisisScreen.title,
                    child: _body(titleSize),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(double titleSize) {
    final view = widget.view;
    final helpline = view.helpline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            CrisisScreen.title,
            style: KoiText.display(
              fontSize: titleSize,
              fontWeight: FontWeight.w700,
              color: CrisisScreen.textColor,
              height: 1.25,
            ),
          ),
        ),
        Text(CrisisScreen.description, style: _text(16, height: 1.55)),
        const SizedBox(height: 16),
        _contentBox(view),
        const SizedBox(height: 12),
        Text(
          '${helpline.name}: ${helpline.number}',
          key: const Key('crisis-helpline'),
          style: _text(16, height: 1.5),
        ),
        const SizedBox(height: 10),
        // TODO(helpline): 1166 is not verified (contract §5).
        NeoButton(
          key: const Key('crisis-call'),
          variant: NeoButtonVariant.secondary,
          fullWidth: true,
          onPressed: () => widget.openUrl(CrisisScreen.telUri(helpline.number)),
          child: Text(CrisisScreen.callLabel(helpline.number)),
        ),
        const SizedBox(height: 20),
        for (final path in CrisisPath.values) ...[
          _choice(path),
          if (path != CrisisPath.values.last) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _contentBox(CrisisView view) {
    final content = view.content;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: CrisisScreen.contentBg,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (view.limitedInformation)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  CrisisScreen.limitedInformation,
                  key: const Key('crisis-limited'),
                  style: _text(15, height: 1.5),
                ),
              ),
            if (content == null)
              Text(
                CrisisScreen.unavailable,
                key: const Key('crisis-unavailable'),
                style: _text(16, height: 1.5),
              )
            else ...[
              for (final (i, item)
                  in content.items.take(InterventionContent.maxItems).indexed)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                  child: Text(
                    item.text,
                    key: Key('crisis-item-$i'),
                    style: _text(16, height: 1.5),
                  ),
                ),
              if (content.source == InterventionSource.fallback)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    CrisisScreen.fallbackLabel,
                    key: const Key('crisis-source'),
                    style: _text(12.8, color: CrisisScreen.sourceColor),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _choice(CrisisPath path) => Material(
    color: Colors.white,
    shape: const RoundedRectangleBorder(
      side: BorderSide(color: CrisisScreen.choiceBorder),
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: Key('crisis-path-${path.wire}'),
      onTap: () => _choose(path),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(CrisisScreen.pathLabels[path]!, style: _text(16)),
          ),
        ),
      ),
    ),
  );
}
