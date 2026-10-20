import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_widgets.dart' show KoiBackButton, koiMinTouch;
import '../care/care_strings.dart';
import '../care/care_widgets.dart' show CareButtonLabel;
import '../widgets/koi_loader.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_input.dart';
import 'safety_plan_models.dart';
import 'safety_plan_providers.dart';
import 'safety_plan_view.dart';
import 'text_direction.dart';

enum _SaveState { idle, saving, saved, failed }

/// Writing the plan: every section has its helper line and up to 10 items
/// of up to 300 characters, which can be added, edited, deleted and moved.
/// Every change is saved at once (encrypted, on this device only), so
/// nothing is lost when the screen is left.
///
/// [onDone] (onboarding) replaces the default "pop" of Back / Done.
class SafetyPlanEditor extends ConsumerStatefulWidget {
  const SafetyPlanEditor({super.key, this.onDone});

  final VoidCallback? onDone;

  @override
  ConsumerState<SafetyPlanEditor> createState() => _SafetyPlanEditorState();
}

class _SafetyPlanEditorState extends ConsumerState<SafetyPlanEditor> {
  SafetyPlan? _plan;

  /// Whose plan [_plan] is: another uid (account switch) starts over, so
  /// one account's plan is never shown or saved for another.
  String? _planUid;
  _SaveState _save = _SaveState.idle;
  Future<void> _lastSave = Future.value();

  /// The open inline editor: its section and item id (null = a new item).
  (SafetyPlanSection, String?)? _editing;
  final _text = TextEditingController();
  final _phone = TextEditingController();
  bool _phoneInvalid = false;
  int _seq = 0;

  @override
  void dispose() {
    _text.dispose();
    _phone.dispose();
    super.dispose();
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_seq++}';

  void _apply(SafetyPlanController c, SafetyPlan next) {
    setState(() {
      _plan = next;
      _save = _SaveState.saving;
    });
    // One save at a time, in order; the last one wins.
    _lastSave = _lastSave.then((_) async {
      try {
        await c.save(next);
        if (mounted && identical(_plan, next)) {
          setState(() => _save = _SaveState.saved);
        }
      } catch (e) {
        debugPrint('KOI: safety plan not saved: ${e.runtimeType}');
        if (mounted) setState(() => _save = _SaveState.failed);
      }
    });
  }

  void _startEdit(SafetyPlanSection s, [SafetyPlanItem? item]) {
    setState(() {
      _editing = (s, item?.id);
      _text.text = item?.text ?? '';
      _phone.text = item?.phone ?? '';
      _phoneInvalid = false;
    });
  }

  void _cancelEdit() => setState(() => _editing = null);

  void _commitEdit(SafetyPlanController c) {
    final editing = _editing;
    final plan = _plan;
    if (editing == null || plan == null) return;
    final (section, id) = editing;
    final phone = _phone.text.trim();
    if (section.hasPhone &&
        phone.isNotEmpty &&
        SafetyPlanItem.clean(id: 'x', text: 'x', phone: phone)?.phone == null) {
      setState(() => _phoneInvalid = true);
      return;
    }
    final item = SafetyPlanItem.clean(
      id: id ?? _newId(),
      text: _text.text,
      phone: section.hasPhone ? phone : null,
    );
    final list = [...plan[section]];
    if (item == null) {
      if (id != null) list.removeWhere((i) => i.id == id);
    } else if (id == null) {
      if (list.length < SafetyPlan.maxItems) list.add(item);
    } else {
      final at = list.indexWhere((i) => i.id == id);
      if (at >= 0) list[at] = item;
    }
    _editing = null;
    _apply(c, plan.withSection(section, list));
  }

  void _delete(SafetyPlanController c, SafetyPlanSection s, String id) {
    final plan = _plan!;
    if (_editing?.$2 == id) _editing = null;
    _apply(
      c,
      plan.withSection(s, [...plan[s]]..removeWhere((i) => i.id == id)),
    );
  }

  void _move(SafetyPlanController c, SafetyPlanSection s, int from, int to) {
    final plan = _plan!;
    final list = [...plan[s]];
    if (to < 0 || to >= list.length) return;
    list.insert(to, list.removeAt(from));
    _apply(c, plan.withSection(s, list));
  }

  Future<void> _done() async {
    await _lastSave;
    if (!mounted) return;
    final onDone = widget.onDone;
    if (onDone != null) {
      onDone();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(careStringsProvider);
    final uid = ref.watch(safetyPlanUidProvider);
    final c = uid == null ? null : ref.watch(safetyPlanControllerProvider(uid));
    if (uid != _planUid) {
      _planUid = uid;
      _plan = null;
      _editing = null;
    }
    if (c != null && !c.loading && !c.unreadable) {
      _plan ??= c.plan ?? SafetyPlan.empty;
    }
    final plan = _plan;
    return Directionality(
      textDirection: s.direction,
      child: PopScope<Object?>(
        canPop: widget.onDone == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _done();
        },
        child: Scaffold(
          backgroundColor: SafetyPlanColors.background,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: KoiBackButton(
                      label: s.t(CareText.back),
                      onTap: _done,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(
                      s.t(CareText.spTitle),
                      style: planHeading(s, 28),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(s.t(CareText.spIntro), style: planText(s, size: 16)),
                  const SizedBox(height: 4),
                  Text(
                    s.t(CareText.spPrivacy),
                    style: planText(s, size: 14, color: SafetyPlanColors.muted),
                  ),
                  const SizedBox(height: 16),
                  if (c != null && c.unreadable)
                    Text(
                      s.t(CareText.spLoadError),
                      key: const Key('sp-editor-unavailable'),
                      style: planText(s),
                    )
                  else if (c == null || plan == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: KoiLoader(label: s.t(CareText.spLoading)),
                    )
                  else ...[
                    for (final section in SafetyPlanSection.values)
                      _section(c, s, plan, section),
                    _status(s),
                    const SizedBox(height: 12),
                    NeoButton(
                      key: const Key('sp-done'),
                      fullWidth: true,
                      onPressed: _done,
                      child: CareButtonLabel(s.t(CareText.spDone)),
                    ),
                  ],
                  SafetyPlanFootnote(strings: s),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _status(CareStrings s) {
    final text = switch (_save) {
      _SaveState.idle => '',
      _SaveState.saving => s.t(CareText.spSaving),
      _SaveState.saved => s.t(CareText.spSaved),
      _SaveState.failed => s.t(CareText.spNotSaved),
    };
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        key: const Key('sp-save-status'),
        style: planText(s, size: 14, color: SafetyPlanColors.muted),
      ),
    );
  }

  Widget _section(
    SafetyPlanController c,
    CareStrings s,
    SafetyPlan plan,
    SafetyPlanSection section,
  ) {
    final items = plan[section];
    final editing = _editing;
    final full = items.length >= SafetyPlan.maxItems;
    return Padding(
      key: Key('sp-edit-${section.id}'),
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: SafetyPlanColors.card,
          borderRadius: BorderRadius.circular(14),
          border: const BorderDirectional(
            start: BorderSide(color: SafetyPlanColors.accent, width: 4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(s.t(sectionTitle(section)), style: planHeading(s)),
              ),
              const SizedBox(height: 4),
              Text(
                s.t(sectionHelp(section)),
                key: Key('sp-help-${section.id}'),
                style: planText(s, size: 15, color: SafetyPlanColors.muted),
              ),
              if (section == SafetyPlanSection.professionals) _fixedHelpline(s),
              for (final (i, item) in items.indexed)
                editing != null &&
                        editing.$1 == section &&
                        editing.$2 == item.id
                    ? _inlineEditor(c, s, section)
                    : _itemRow(c, s, section, item, i, items.length),
              if (editing != null &&
                  editing.$1 == section &&
                  editing.$2 == null)
                _inlineEditor(c, s, section)
              else if (full)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    s.t(CareText.spMaxItems),
                    key: Key('sp-max-${section.id}'),
                    style: planText(s, size: 14, color: SafetyPlanColors.muted),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: NeoButton(
                    key: Key('sp-add-${section.id}'),
                    variant: NeoButtonVariant.secondary,
                    fullWidth: true,
                    onPressed: editing == null
                        ? () => _startEdit(section)
                        : null,
                    child: CareButtonLabel('+ ${s.t(CareText.spAdd)}'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fixedHelpline(CareStrings s) {
    const h = SafetyPlanView.helpline;
    return Padding(
      key: const Key('sp-edit-helpline'),
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(h.name, style: planText(s, size: 16)),
              Text(
                h.number,
                textDirection: TextDirection.ltr,
                style: planText(s, size: 16, weight: FontWeight.w700),
              ),
              Text(
                s.t(CareText.spHelplineFixed),
                style: planText(s, size: 13, color: SafetyPlanColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemRow(
    SafetyPlanController c,
    CareStrings s,
    SafetyPlanSection section,
    SafetyPlanItem item,
    int index,
    int count,
  ) {
    final busy = _editing != null;
    Widget action(String key, IconData icon, String label, VoidCallback? f) =>
        IconButton(
          key: Key('sp-$key-${item.id}'),
          tooltip: label,
          constraints: const BoxConstraints.tightFor(
            width: koiMinTouch,
            height: koiMinTouch,
          ),
          color: SafetyPlanColors.text,
          disabledColor: SafetyPlanColors.muted.withValues(alpha: 0.4),
          onPressed: busy ? null : f,
          icon: Icon(icon, size: 22),
        );
    return Padding(
      key: Key('sp-row-${item.id}'),
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item.text,
                textDirection: userTextDirection(item.text),
                style: planText(s, size: 16),
              ),
              if (item.phone != null)
                Text(
                  item.phone!,
                  textDirection: TextDirection.ltr,
                  style: planText(s, size: 15, weight: FontWeight.w700),
                ),
              Wrap(
                alignment: WrapAlignment.end,
                children: [
                  action(
                    'up',
                    Icons.arrow_upward,
                    s.t(CareText.spMoveUp),
                    index == 0
                        ? null
                        : () => _move(c, section, index, index - 1),
                  ),
                  action(
                    'down',
                    Icons.arrow_downward,
                    s.t(CareText.spMoveDown),
                    index == count - 1
                        ? null
                        : () => _move(c, section, index, index + 1),
                  ),
                  action(
                    'edit',
                    Icons.edit_outlined,
                    s.t(CareText.spEditItem),
                    () => _startEdit(section, item),
                  ),
                  action(
                    'delete',
                    Icons.delete_outline,
                    s.t(CareText.spDelete),
                    () => _delete(c, section, item.id),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inlineEditor(
    SafetyPlanController c,
    CareStrings s,
    SafetyPlanSection section,
  ) => Padding(
    key: const Key('sp-inline-editor'),
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: s.t(sectionTitle(section)),
          textField: true,
          child: NeoInput(
            key: const Key('sp-input-text'),
            label: s.t(CareText.spItemLabel),
            controller: _text,
            multiline: true,
            maxLength: SafetyPlanItem.maxText,
            textDirection: userTextDirection(_text.text) ?? s.direction,
            onChanged: (_) => setState(() {}),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            s.charCount(_text.text.length, SafetyPlanItem.maxText),
            key: const Key('sp-char-count'),
            textDirection: TextDirection.ltr,
            style: planText(s, size: 13, color: SafetyPlanColors.muted),
          ),
        ),
        if (section.hasPhone) ...[
          const SizedBox(height: 8),
          NeoInput(
            key: const Key('sp-input-phone'),
            label: s.t(CareText.spPhoneLabel),
            controller: _phone,
            keyboardType: TextInputType.phone,
            maxLength: SafetyPlanItem.maxPhone,
            textDirection: TextDirection.ltr,
            error: _phoneInvalid ? s.t(CareText.spPhoneInvalid) : null,
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.end,
          children: [
            NeoButton(
              key: const Key('sp-item-cancel'),
              variant: NeoButtonVariant.ghost,
              onPressed: _cancelEdit,
              child: CareButtonLabel(s.t(CareText.spCancel)),
            ),
            NeoButton(
              key: const Key('sp-item-save'),
              onPressed: _text.text.trim().isEmpty
                  ? null
                  : () => _commitEdit(c),
              child: CareButtonLabel(s.t(CareText.spSaveItem)),
            ),
          ],
        ),
      ],
    ),
  );
}
