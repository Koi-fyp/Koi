import 'package:flutter/widgets.dart';

import 'top_nav.dart';

/// Lets a page inside a tab switch the shell's tab (e.g. Settings → the
/// Care tab). AppShell provides it; outside the shell there is none.
class ShellTabs extends InheritedWidget {
  const ShellTabs({super.key, required this.select, required super.child});

  final void Function(KoiTab tab) select;

  static ShellTabs? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellTabs>();

  @override
  bool updateShouldNotify(ShellTabs oldWidget) => false;
}
