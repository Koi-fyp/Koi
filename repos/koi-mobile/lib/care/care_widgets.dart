import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_widgets.dart';
import '../app/providers.dart';
import '../core/auth/auth_service.dart';
import '../platform/demo_badge.dart';
import '../shell/svg_path.dart';
import '../theme/koi_colors.dart';
import '../theme/koi_radii.dart';
import '../widgets/koi_loader.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_card.dart';
import '../widgets/neo_input.dart';
import 'care_api_support.dart';
import 'care_session.dart';
import 'care_strings.dart';

// MOB-2 building blocks, made ONLY from the KOI design system and the
// MOB-1 widgets (KoiPage layout, KoiBackButton, KoiNoticeCard, KoiLoader,
// NeoSkeletonList, NeoButton, NeoCard, NeoInput). Every page takes the
// Care language's direction (Urdu right-to-left).

TextStyle careBody(
  CareStrings s, {
  double size = 15,
  FontWeight weight = FontWeight.w400,
  Color color = KoiColors.neoBlack,
}) => koiBodyStyle(
  size: size,
  weight: weight,
  color: color,
).copyWith(height: s.lineHeight);

TextStyle careMuted(CareStrings s, [double size = 13.5]) =>
    careBody(s, size: size, color: KoiColors.koiDark);

/// The KoiPage layout (background, safe area, 20dp gutter, back + Demo
/// badge row, title) with pull-to-refresh, an optional [bottom] bar and
/// the Care direction.
class CarePage extends ConsumerWidget {
  const CarePage({
    super.key,
    required this.children,
    this.title,
    this.back = true,
    this.demo = false,
    this.onRefresh,
    this.bottom,
    this.controller,
  });

  final String? title;
  final List<Widget> children;
  final bool back;
  final bool demo;
  final Future<void> Function()? onRefresh;
  final Widget? bottom;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(careStringsProvider);
    final list = ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        if (back || demo)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                if (back) KoiBackButton(label: s.t(CareText.back)),
                const Spacer(),
                if (demo) const DemoDataBadge(),
              ],
            ),
          ),
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(
              header: true,
              child: Text(
                title!,
                style: koiTitleStyle().copyWith(height: s.isUrdu ? 1.6 : null),
              ),
            ),
          ),
        ...children,
      ],
    );
    final refresh = onRefresh;
    return Directionality(
      textDirection: s.direction,
      child: Scaffold(
        backgroundColor: KoiColors.background,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: refresh == null
                    ? list
                    : RefreshIndicator(
                        color: KoiColors.neoBlack,
                        backgroundColor: KoiColors.neoWhite,
                        onRefresh: refresh,
                        child: list,
                      ),
              ),
              ?bottom,
            ],
          ),
        ),
      ),
    );
  }
}

/// The loading / error / not-available / empty / data states of a
/// [CareList], in the MOB-1 notice-card style with a Retry. [items] (when
/// given) replaces the list's own items, e.g. filtered or grouped.
List<Widget> careListStates<T>({
  required CareStrings s,
  required CareList<Object?> list,
  required String loadingLabel,
  required String emptyText,
  required Widget Function(T item) item,
  List<T>? items,
}) {
  final shown = items ?? list.items.cast<T>();
  final error = list.error;
  if (list.isLoading) return [NeoSkeletonList(label: loadingLabel)];
  if (!list.loaded) {
    if (error == null) return [NeoSkeletonList(label: loadingLabel)];
    final notAvailable = careFailureOf(error) == CareFailure.notAvailable;
    return [
      KoiNoticeCard(
        key: Key(notAvailable ? 'care-not-available' : 'care-error'),
        message: careFailureText(s, error),
        action: notAvailable ? null : list.refresh,
        actionLabel: s.t(CareText.retry),
      ),
    ];
  }
  return [
    if (list.isUpdating) CareUpdating(strings: s),
    if (error != null)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: KoiErrorText(careFailureText(s, error)),
      ),
    if (shown.isEmpty)
      KoiNoticeCard(key: const Key('care-empty'), message: emptyText)
    else
      for (final i in shown)
        Padding(padding: const EdgeInsets.only(bottom: 14), child: item(i)),
    if (list.hasMore)
      list.isLoadingMore
          ? KoiLoader(compact: true, label: s.t(CareText.loading))
          : NeoButton(
              key: const Key('care-load-more'),
              variant: NeoButtonVariant.ghost,
              fullWidth: true,
              onPressed: list.loadMore,
              child: CareButtonLabel(s.t(CareText.loadMore)),
            ),
  ];
}

/// The subtle "Updating…" line over cached data.
class CareUpdating extends StatelessWidget {
  const CareUpdating({super.key, required this.strings});
  final CareStrings strings;

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('care-updating'),
    padding: const EdgeInsets.only(bottom: 12),
    child: KoiLoader(compact: true, label: strings.t(CareText.updating)),
  );
}

/// A status pill (Neo border, KOI tokens). Dark text on every fill
/// (neoYellow / neoMint / neoGray / neoWhite all ≥ 4.5:1 with black).
class CareChip extends StatelessWidget {
  const CareChip({super.key, required this.label, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color ?? KoiColors.neoGray,
      border: Border.all(width: 2),
      borderRadius: KoiRadii.pillAll,
    ),
    child: Text(
      label,
      style: koiBodyStyle(size: 12.5, weight: FontWeight.w700),
    ),
  );
}

/// A tappable Neo card row with a 48dp+ target.
class CareCard extends StatelessWidget {
  const CareCard({
    super.key,
    required this.child,
    this.onTap,
    this.semanticsLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: semanticsLabel,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: NeoCard(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: koiMinTouch),
          child: child,
        ),
      ),
    ),
  );
}

/// A NeoButton label that wraps onto a second line instead of overflowing
/// at 360dp (NeoButton lays its child out in a Row with softWrap off).
class CareButtonLabel extends StatelessWidget {
  const CareButtonLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Flexible(child: Text(text, softWrap: true, textAlign: TextAlign.center));
}

/// A primary action that turns into the KoiLoader while it runs (never a
/// final state before the server answers).
class CareActionButton extends StatelessWidget {
  const CareActionButton({
    super.key,
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.onPressed,
    this.variant = NeoButtonVariant.primary,
  });

  final String label;
  final String busyLabel;
  final bool busy;
  final VoidCallback? onPressed;
  final NeoButtonVariant variant;

  @override
  Widget build(BuildContext context) => busy
      ? Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: KoiLoader(compact: true, label: busyLabel),
        )
      : ConstrainedBox(
          constraints: const BoxConstraints(minHeight: koiMinTouch),
          child: NeoButton(
            variant: variant,
            fullWidth: true,
            onPressed: onPressed,
            child: CareButtonLabel(label),
          ),
        );
}

/// A consent checkbox row in the onboarding AI-disclosure style (22dp Neo
/// box, neoBlue when ticked, white check; ai_disclosure_step.dart
/// _CheckRow), with a 48dp row target.
class CareCheckRow extends StatelessWidget {
  const CareCheckRow({
    super.key,
    required this.label,
    required this.checked,
    required this.onChanged,
    required this.strings,
  });

  final String label;
  final bool checked;
  final VoidCallback onChanged;
  final CareStrings strings;

  static final Path _check = parseSvgPath('M2 6l3 3 5-5');

  @override
  Widget build(BuildContext context) => Semantics(
    checked: checked,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: koiMinTouch),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.ease,
              margin: const EdgeInsets.only(top: 1),
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: checked ? KoiColors.neoBlue : KoiColors.neoWhite,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(width: 2.5),
                boxShadow: const [BoxShadow(offset: Offset(2, 2))],
              ),
              child: checked
                  ? SizedBox.square(
                      dimension: 13,
                      child: CustomPaint(painter: _CheckPainter(_check)),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: careBody(strings, size: 14.4))),
          ],
        ),
      ),
    ),
  );
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.path);
  final Path path;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 12, size.height / 12);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = KoiColors.neoWhite
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => false;
}

/// A confirm dialog in the Settings sign-out dialog style.
Future<bool> showCareConfirm(
  BuildContext context,
  CareStrings s, {
  required String title,
  required String body,
  required String yes,
  required String no,
  Key? yesKey,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => Directionality(
      textDirection: s.direction,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(20),
        child: NeoCard(
          variant: NeoCardVariant.elevated,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: koiTitleStyle(22)),
              const SizedBox(height: 8),
              Text(body, style: careBody(s)),
              const SizedBox(height: 20),
              NeoButton(
                key: yesKey ?? const Key('care-confirm-yes'),
                fullWidth: true,
                onPressed: () => Navigator.of(context).pop(true),
                child: CareButtonLabel(yes),
              ),
              const SizedBox(height: 10),
              NeoButton(
                key: const Key('care-confirm-no'),
                variant: NeoButtonVariant.ghost,
                fullWidth: true,
                onPressed: () => Navigator.of(context).pop(false),
                child: CareButtonLabel(no),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return ok == true;
}

/// The recent-sign-in re-check (extra rule 4): a mutation's 401
/// `unauthenticated` asks for the password again. It never ends access,
/// never refreshes capabilities and never closes a screen. Returns true
/// when the password was confirmed.
Future<bool> showReauthSheet(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _ReauthDialog(),
  );
  return ok == true;
}

class _ReauthDialog extends ConsumerStatefulWidget {
  const _ReauthDialog();

  @override
  ConsumerState<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends ConsumerState<_ReauthDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final s = ref.read(careStringsProvider);
    if (_password.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).reauthenticate(_password.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is AccountAuthException
            ? s.t(CareText.reauthWrong)
            : s.t(CareText.genericError);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(careStringsProvider);
    return Directionality(
      textDirection: s.direction,
      child: Dialog(
        key: const Key('care-reauth'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(20),
        child: NeoCard(
          variant: NeoCardVariant.elevated,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.t(CareText.reauthTitle), style: koiTitleStyle(22)),
              const SizedBox(height: 8),
              Text(s.t(CareText.reauthBody), style: careBody(s)),
              const SizedBox(height: 16),
              NeoInput(
                key: const Key('care-reauth-password'),
                label: s.t(CareText.reauthPassword),
                controller: _password,
                obscureText: true,
                enabled: !_busy,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                KoiErrorText(_error!),
              ],
              const SizedBox(height: 18),
              CareActionButton(
                key: const Key('care-reauth-confirm'),
                label: s.t(CareText.reauthConfirm),
                busyLabel: s.t(CareText.loading),
                busy: _busy,
                onPressed: _confirm,
              ),
              const SizedBox(height: 10),
              NeoButton(
                key: const Key('care-reauth-cancel'),
                variant: NeoButtonVariant.ghost,
                fullWidth: true,
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: CareButtonLabel(s.t(CareText.reauthCancel)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Runs one Care mutation. A recent-sign-in 401 opens the re-check and,
/// once confirmed, retries the SAME call (same idempotency key, captured by
/// [call]) exactly once more. Returns the value, or throws the failure for
/// the screen to show inline.
Future<T> runCareMutation<T>(
  BuildContext context,
  WidgetRef ref,
  Future<T> Function() call,
) async {
  try {
    return await call();
  } catch (e) {
    if (careFailureOf(e) != CareFailure.reauth || !context.mounted) rethrow;
    if (!await showReauthSheet(context, ref)) rethrow;
    return call();
  }
}
