import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../care/care_strings.dart';
import '../safety_plan/safety_plan_providers.dart';
import '../safety_plan/safety_plan_view.dart' show SafetyPlanView;
import '../settings/widgets/settings_widgets.dart'
    show SettingsToastLayer, ToastMessage, ToastType;
import 'breathing_screen.dart';
import 'crisis_screen.dart';
import 'safety_controller.dart';
import 'safety_providers.dart';

/// Shows the crisis and breathing screens on the root navigator whenever
/// [SafetyController] says so, above whatever is open (Chat, the avatar
/// call screen, Settings pages). The crisis screen always wins: it replaces
/// a running breathing screen.
///
/// Notices (Web's exerciseNotice texts) appear as the usual toast over the
/// shell.
class SafetyHost extends ConsumerStatefulWidget {
  const SafetyHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SafetyHost> createState() => _SafetyHostState();
}

class _SafetyHostState extends ConsumerState<SafetyHost> {
  late final SafetyController _c = ref.read(safetyControllerProvider);
  Route<void>? _crisisRoute;
  Route<void>? _breathingRoute;
  Route<void>? _planRoute;
  int _noticeSeq = 0;
  ToastMessage? _toast;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onChange());
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _remove(_crisisRoute);
    _remove(_breathingRoute);
    _remove(_planRoute);
    super.dispose();
  }

  void _remove(Route<void>? route) {
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  void _onChange() {
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);

    // Crisis first: close breathing before opening it.
    if (_c.breathing == null || _c.crisis != null) {
      _remove(_breathingRoute);
      _breathingRoute = null;
    }
    if (_c.crisis == null) {
      _remove(_planRoute);
      _planRoute = null;
      _remove(_crisisRoute);
      _crisisRoute = null;
    }

    final view = _c.crisis;
    if (view != null && _crisisRoute == null) {
      final route = PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: false,
        settings: const RouteSettings(name: 'crisis'),
        pageBuilder: (context, _, _) => ListenableBuilder(
          listenable: _c,
          builder: (context, _) => Consumer(
            builder: (context, ref, _) => CrisisScreen(
              // The open screen may get its content filled in later.
              view: _c.crisis ?? view,
              onChoose: _c.chooseCrisisPath,
              onOpenSafetyPlan: _safetyPlanOpener(ref),
              safetyPlanLabel: _safetyPlanLabel(ref),
            ),
          ),
        ),
      );
      _crisisRoute = route;
      nav.push(route);
    } else if (_c.breathing != null &&
        _c.crisis == null &&
        _breathingRoute == null) {
      final route = MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'breathing'),
        builder: (_) => BreathingScreen(controller: _c),
      );
      _breathingRoute = route;
      nav.push(route);
    }

    if (_c.noticeSeq != _noticeSeq && _c.notice != null) {
      _noticeSeq = _c.noticeSeq;
      setState(
        () => _toast = ToastMessage(_c.notice!, ToastType.info, _noticeSeq),
      );
    }
  }

  /// The crisis screen's "Open my safety plan": only when the signed-in
  /// user's plan has loaded and has something in it. Loading, no plan or
  /// any error = null (no button); the crisis screen and its helpline are
  /// never held back or broken by the plan.
  VoidCallback? _safetyPlanOpener(WidgetRef ref) {
    try {
      final uid = ref.watch(safetyPlanUidProvider);
      if (uid == null) return null;
      if (!ref.watch(safetyPlanControllerProvider(uid)).hasPlan) return null;
      return _openSafetyPlan;
    } catch (e) {
      debugPrint('KOI: crisis safety plan button hidden: ${e.runtimeType}');
      return null;
    }
  }

  String _safetyPlanLabel(WidgetRef ref) {
    try {
      return ref.watch(careStringsProvider).t(CareText.spOpen);
    } catch (_) {
      return CrisisScreen.defaultSafetyPlanLabel;
    }
  }

  /// Read only, above the crisis screen. Touches nothing in the
  /// SafetyController: no path, no resolution, no event; Back returns to
  /// the crisis screen exactly as it was.
  void _openSafetyPlan() {
    if (!mounted || _c.crisis == null) return;
    if (_planRoute?.isActive ?? false) return;
    final route = MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'crisis-safety-plan'),
      builder: (_) => const SafetyPlanView(fromCrisis: true),
    );
    _planRoute = route;
    Navigator.of(context, rootNavigator: true).push(route).whenComplete(() {
      if (identical(_planRoute, route)) _planRoute = null;
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      SettingsToastLayer(
        toast: _toast,
        onClose: () => setState(() => _toast = null),
      ),
    ],
  );
}
