import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          builder: (context, _) => CrisisScreen(
            // The open screen may get its content filled in later.
            view: _c.crisis ?? view,
            onChoose: _c.chooseCrisisPath,
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
