import 'package:flutter/material.dart';

import '../account/account_widgets.dart';
import '../care/care_strings.dart';
import '../theme/koi_colors.dart';
import '../theme/koi_radii.dart';
import '../theme/koi_shadows.dart';
import '../theme/koi_text.dart';
import '../widgets/koi_loader.dart';
import '../widgets/neo_input.dart';
import 'asset_manifest.dart';
import 'questionnaire_models.dart';

/// Style for PUBLISHED questionnaire wording only. Urdu-script
/// questionnaires use Noto Nastaliq Urdu (bundled, OFL; its own tall line
/// metrics); English and Roman Urdu keep the theme's DM Sans. App chrome
/// (buttons, status lines) never uses this.
TextStyle questionnaireTextStyle(
  QuestionnaireLanguage language, {
  double size = 16,
  FontWeight weight = FontWeight.w400,
  Color color = KoiColors.neoBlack,
}) => language.isUrduScript
    ? KoiText.urduQuestionnaire(fontSize: size, color: color)
    : koiBodyStyle(size: size, weight: weight, color: color);

/// One question of a published questionnaire, in [language]. The direction
/// comes from the screen ([QuestionnaireLanguage.direction]). Wording and
/// option labels are shown exactly as published: never trimmed, shortened
/// or reworded.
class QuestionView extends StatelessWidget {
  const QuestionView({
    super.key,
    required this.question,
    required this.language,
    required this.answer,
    required this.onChanged,
    required this.manifest,
    required this.strings,
    this.enabled = true,
  });

  final Question question;
  final QuestionnaireLanguage language;
  final Answer? answer;
  final ValueChanged<AnswerValue> onChanged;
  final QuestionnaireAssetManifest manifest;
  final CareStrings strings;
  final bool enabled;

  void _toggle(String optionId) {
    final current = answer?.optionIds ?? const <String>[];
    if (question.type.isMulti) {
      onChanged(
        AnswerValue(
          optionIds: current.contains(optionId)
              ? [
                  for (final id in current)
                    if (id != optionId) id,
                ]
              : [...current, optionId],
        ),
      );
    } else {
      onChanged(AnswerValue(optionIds: [optionId]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = answer?.optionIds ?? const <String>[];
    final q = question;
    // At max_selections the other options are disabled (answers.ts refuses
    // more).
    final full = q.type.isMulti && selected.length >= q.selectionLimit;
    VoidCallback? tap(String id) =>
        enabled && (!full || selected.contains(id)) ? () => _toggle(id) : null;
    // A picture question is shown as pictures only when EVERY option has a
    // bundled picture matching its full reference; otherwise as text tiles.
    final pictures =
        q.type.isImage &&
        q.options.every((o) => manifest.resolveReference(o.asset) != null);
    return Column(
      key: Key('question-${q.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            q.prompt.resolve(language),
            key: const Key('question-text'),
            style: questionnaireTextStyle(
              language,
              size: 19,
              weight: FontWeight.w700,
            ),
          ),
        ),
        if (!q.required)
          Text(
            strings.t(CareText.qOptional),
            style: koiMutedStyle(13).copyWith(height: strings.lineHeight),
          ),
        if (q.type.isMulti) ...[
          if (_limits(q) case final hint?)
            Text(
              hint,
              key: const Key('multi-limits'),
              style: koiMutedStyle(13).copyWith(height: strings.lineHeight),
            ),
        ],
        const SizedBox(height: 16),
        switch (q.type) {
          QuestionType.shortText => _FreeText(
            key: ValueKey('free-text-${q.id}'),
            initial: answer?.text ?? '',
            max: q.maxLength,
            strings: strings,
            enabled: enabled,
            onChanged: (t) => onChanged(AnswerValue(text: t)),
          ),
          QuestionType.yesNo => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final yes in const [true, false]) ...[
                if (!yes) const SizedBox(width: 12),
                Expanded(
                  child: _ChoiceTile(
                    id: yes ? 'yes' : 'no',
                    label: yes ? language.yes : language.no,
                    language: language,
                    selected: answer?.yes == yes,
                    multi: false,
                    asButton: true,
                    onTap: enabled
                        ? () => onChanged(AnswerValue(yes: yes))
                        : null,
                  ),
                ),
              ],
            ],
          ),
          _ when pictures => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final o in q.options)
                _ImageTile(
                  option: o,
                  language: language,
                  asset: manifest.resolveReference(o.asset)!,
                  selected: selected.contains(o.id),
                  multi: q.type.isMulti,
                  onTap: tap(o.id),
                ),
            ],
          ),
          _ => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final o in q.options)
                _ChoiceTile(
                  id: o.id,
                  label: o.label.resolve(language),
                  language: language,
                  selected: selected.contains(o.id),
                  multi: q.type.isMulti,
                  onTap: tap(o.id),
                ),
            ],
          ),
        },
        if (isBelowMinimum(q, answer)) ...[
          const SizedBox(height: 4),
          KoiErrorText(
            strings.chooseAtLeast(q.minSelections),
            key: const Key('multi-below-min'),
          ),
        ],
      ],
    );
  }

  /// "Choose at least N · Choose up to M" when the question limits the
  /// selection (null when any number of options may be chosen).
  String? _limits(Question q) {
    final parts = [
      if (q.minSelections > 1) strings.chooseAtLeast(q.minSelections),
      if (q.selectionLimit < q.options.length)
        strings.chooseUpTo(q.selectionLimit),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// A selectable answer: white Neo tile, yellow + hard shadow when chosen.
/// Radio semantics for single choice / likert / yes_no, checkbox for
/// multi. [asButton]: yes_no's two side-by-side buttons (centred label,
/// no mark).
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.id,
    required this.label,
    required this.language,
    required this.selected,
    required this.multi,
    required this.onTap,
    this.asButton = false,
  });

  final String id;
  final String label;
  final QuestionnaireLanguage language;
  final bool selected;
  final bool multi;
  final bool asButton;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final reduce = koiReduceMotion(context);
    final text = Text(
      label,
      textAlign: asButton ? TextAlign.center : null,
      style: questionnaireTextStyle(
        language,
        weight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        key: Key('option-$id'),
        inMutuallyExclusiveGroup: !multi,
        checked: selected,
        button: asButton,
        enabled: onTap != null,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            alignment: asButton ? Alignment.center : null,
            decoration: BoxDecoration(
              color: selected ? KoiColors.neoYellow : KoiColors.neoWhite,
              border: Border.all(width: 2.5),
              borderRadius: KoiRadii.inputAll,
              boxShadow: selected ? KoiShadows.neoMd : KoiShadows.neoSm,
            ),
            child: asButton
                ? text
                : Row(
                    children: [
                      _Mark(selected: selected, multi: multi),
                      const SizedBox(width: 12),
                      Expanded(child: text),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.selected, required this.multi});
  final bool selected;
  final bool multi;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: KoiColors.neoWhite,
      border: Border.all(width: 2),
      shape: multi ? BoxShape.rectangle : BoxShape.circle,
      borderRadius: multi ? BorderRadius.circular(5) : null,
    ),
    child: selected
        ? Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: KoiColors.neoBlack,
              shape: multi ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: multi ? BorderRadius.circular(2) : null,
            ),
          )
        : null,
  );
}

/// A picture option from the bundled asset library (its full
/// `{asset_id, version, sha256}` matched). A file that fails to load shows
/// the label: never another picture, never a remote load.
class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.option,
    required this.language,
    required this.asset,
    required this.selected,
    required this.multi,
    required this.onTap,
  });

  final QuestionnaireOption option;
  final QuestionnaireLanguage language;
  final QuestionnaireAsset asset;
  final bool selected;
  final bool multi;
  final VoidCallback? onTap;

  static const double side = 132;

  @override
  Widget build(BuildContext context) {
    final label = option.label.resolve(language);
    return Semantics(
      key: Key('option-${option.id}'),
      inMutuallyExclusiveGroup: !multi,
      checked: selected,
      enabled: onTap != null,
      image: true,
      label: '$label. ${asset.visualDescription}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: side,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected ? KoiColors.neoYellow : KoiColors.neoWhite,
            border: Border.all(width: 2.5),
            borderRadius: KoiRadii.inputAll,
            boxShadow: selected ? KoiShadows.neoMd : KoiShadows.neoSm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: side - 36,
                child: Image.asset(
                  asset.path,
                  key: Key('image-${option.id}'),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Center(
                    key: Key('image-fallback-${option.id}'),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: questionnaireTextStyle(language, size: 12.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _Mark(selected: selected, multi: multi),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: questionnaireTextStyle(language, size: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Short text up to the question's `max_length`.
class _FreeText extends StatefulWidget {
  const _FreeText({
    super.key,
    required this.initial,
    required this.max,
    required this.strings,
    required this.enabled,
    required this.onChanged,
  });

  final String initial;
  final int max;
  final CareStrings strings;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_FreeText> createState() => _FreeTextState();
}

class _FreeTextState extends State<_FreeText> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeoInput(
          key: const Key('free-text'),
          controller: _c,
          multiline: true,
          enabled: widget.enabled,
          onChanged: (t) {
            if (t.length > max) {
              _c.text = t.substring(0, max);
              _c.selection = TextSelection.collapsed(offset: max);
            }
            widget.onChanged(_c.text);
            setState(() {});
          },
        ),
        const SizedBox(height: 4),
        Text(
          widget.strings.charCount(_c.text.length, max),
          key: const Key('free-text-count'),
          textAlign: TextAlign.end,
          style: koiMutedStyle(12),
        ),
      ],
    );
  }
}
