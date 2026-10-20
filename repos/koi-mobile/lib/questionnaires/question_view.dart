import 'package:flutter/material.dart';

import '../account/account_widgets.dart';
import '../care/care_strings.dart';
import '../theme/koi_colors.dart';
import '../theme/koi_radii.dart';
import '../theme/koi_shadows.dart';
import '../theme/koi_text.dart';
import '../widgets/koi_loader.dart';
import '../widgets/neo_button.dart';
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

/// Shows a number without a needless ".0" ("5", "2.5").
String formatQuestionnaireNumber(double v) =>
    v == v.roundToDouble() && v.abs() < 1e15
    ? v.toInt().toString()
    : v.toString();

/// Parses what was typed: Western, Urdu (۰-۹) or Arabic-Indic (٠-٩)
/// digits, "." or "," as the decimal mark. Null = not a number.
double? parseQuestionnaireNumber(String raw) {
  final b = StringBuffer();
  for (final r in raw.trim().runes) {
    if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r == 0x2C || r == 0x066B) {
      b.write('.');
    } else {
      b.writeCharCode(r);
    }
  }
  final v = double.tryParse(b.toString());
  return v != null && v.isFinite ? v : null;
}

/// One question of a published questionnaire. The direction comes from
/// the screen (the questionnaire's `rtl`). Wording, help text and option
/// labels are shown exactly as published: never trimmed, shortened or
/// reworded.
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
    VoidCallback? tap(String id) => enabled ? () => _toggle(id) : null;
    return Column(
      key: Key('question-${q.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            q.text,
            key: const Key('question-text'),
            style: questionnaireTextStyle(
              language,
              size: 19,
              weight: FontWeight.w700,
            ),
          ),
        ),
        if (q.helpText != null) ...[
          const SizedBox(height: 6),
          Text(
            q.helpText!,
            key: const Key('question-help'),
            style: questionnaireTextStyle(
              language,
              size: 14.5,
              color: KoiColors.koiDark,
            ),
          ),
        ],
        if (!q.required)
          Text(
            strings.t(CareText.qOptional),
            style: koiMutedStyle(13).copyWith(height: strings.lineHeight),
          ),
        if (q.assetId != null || q.visualDescription != null) ...[
          const SizedBox(height: 12),
          _QuestionPicture(
            question: q,
            language: language,
            asset: manifest.resolve(q.assetId),
          ),
        ],
        const SizedBox(height: 16),
        switch (q.type) {
          QuestionType.freeText => _FreeText(
            key: ValueKey('free-text-${q.id}'),
            initial: answer?.text ?? '',
            language: language,
            strings: strings,
            enabled: enabled,
            onChanged: (t) => onChanged(AnswerValue(text: t)),
          ),
          QuestionType.numeric => _NumericInput(
            key: ValueKey('numeric-${q.id}'),
            question: q,
            initial: answer?.value,
            strings: strings,
            enabled: enabled,
            onChanged: onChanged,
          ),
          QuestionType.imageSingle || QuestionType.imageMulti => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final o in q.options)
                _ImageTile(
                  option: o,
                  language: language,
                  strings: strings,
                  asset: manifest.resolve(o.assetId),
                  selected: selected.contains(o.id),
                  multi: q.type.isMulti,
                  onTap: tap(o.id),
                ),
            ],
          ),
          QuestionType.yesNo => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < q.options.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: _ChoiceTile(
                    option: q.options[i],
                    language: language,
                    selected: selected.contains(q.options[i].id),
                    multi: false,
                    asButton: true,
                    onTap: tap(q.options[i].id),
                  ),
                ),
              ],
            ],
          ),
          _ => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final o in q.options)
                _ChoiceTile(
                  option: o,
                  language: language,
                  selected: selected.contains(o.id),
                  multi: q.type.isMulti,
                  onTap: tap(o.id),
                ),
            ],
          ),
        },
      ],
    );
  }
}

/// A selectable answer: white Neo tile, yellow + hard shadow when chosen.
/// Radio semantics for single choice / likert / yes_no, checkbox for
/// multi. [asButton]: yes_no's two side-by-side buttons (centred label,
/// no mark).
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.option,
    required this.language,
    required this.selected,
    required this.multi,
    required this.onTap,
    this.asButton = false,
  });

  final QuestionnaireOption option;
  final QuestionnaireLanguage language;
  final bool selected;
  final bool multi;
  final bool asButton;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final reduce = koiReduceMotion(context);
    final label = Text(
      option.label,
      textAlign: asButton ? TextAlign.center : null,
      style: questionnaireTextStyle(
        language,
        weight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        key: Key('option-${option.id}'),
        inMutuallyExclusiveGroup: !multi,
        checked: selected,
        button: asButton,
        enabled: onTap != null,
        label: option.label,
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
                ? label
                : Row(
                    children: [
                      _Mark(selected: selected, multi: multi),
                      const SizedBox(width: 12),
                      Expanded(child: label),
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

/// Text in place of a picture: the option's / question's visual
/// description, else the manifest's, else "Picture unavailable".
class _PictureText extends StatelessWidget {
  const _PictureText({super.key, required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Text(text, textAlign: TextAlign.center, style: style),
    ),
  );
}

/// A picture option from the bundled asset library. An unknown asset id,
/// a malformed id or a file that fails to load shows the visual
/// description text: never another picture, never a remote load.
class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.option,
    required this.language,
    required this.strings,
    required this.asset,
    required this.selected,
    required this.multi,
    required this.onTap,
  });

  final QuestionnaireOption option;
  final QuestionnaireLanguage language;
  final CareStrings strings;
  final QuestionnaireAsset? asset;
  final bool selected;
  final bool multi;
  final VoidCallback? onTap;

  static const double side = 132;

  @override
  Widget build(BuildContext context) {
    final a = asset;
    final description =
        option.visualDescription ??
        a?.visualDescription ??
        strings.t(CareText.qPictureUnavailable);
    final fallback = _PictureText(
      key: Key('image-fallback-${option.id}'),
      text: description,
      style: questionnaireTextStyle(
        language,
        size: 12.5,
        color: KoiColors.koiDark,
      ),
    );
    return Semantics(
      key: Key('option-${option.id}'),
      inMutuallyExclusiveGroup: !multi,
      checked: selected,
      enabled: onTap != null,
      image: a != null,
      label: '${option.label}. $description',
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
                child: a == null
                    ? fallback
                    : Image.asset(
                        a.path,
                        key: Key('image-${option.id}'),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => fallback,
                      ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _Mark(selected: selected, multi: multi),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      option.label,
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

/// The question's own picture (or its visual description).
class _QuestionPicture extends StatelessWidget {
  const _QuestionPicture({
    required this.question,
    required this.language,
    required this.asset,
  });

  final Question question;
  final QuestionnaireLanguage language;
  final QuestionnaireAsset? asset;

  @override
  Widget build(BuildContext context) {
    final a = asset;
    final description = question.visualDescription ?? a?.visualDescription;
    final text = description == null
        ? null
        : _PictureText(
            key: const Key('question-picture-text'),
            text: description,
            style: questionnaireTextStyle(
              language,
              size: 14,
              color: KoiColors.koiDark,
            ),
          );
    if (a == null) return text ?? const SizedBox.shrink();
    return Semantics(
      image: true,
      label: description,
      excludeSemantics: true,
      child: SizedBox(
        height: 140,
        child: Image.asset(
          a.path,
          key: const Key('question-picture'),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => text ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _FreeText extends StatefulWidget {
  const _FreeText({
    super.key,
    required this.initial,
    required this.language,
    required this.strings,
    required this.enabled,
    required this.onChanged,
  });

  final String initial;
  final QuestionnaireLanguage language;
  final CareStrings strings;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_FreeText> createState() => _FreeTextState();
}

class _FreeTextState extends State<_FreeText> {
  static const int max = Question.maxTextLength;
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
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
            _c.selection = const TextSelection.collapsed(offset: max);
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

/// A number within `min_value`..`max_value` on the `step` grid. Only a
/// valid number is recorded; anything else shows why and records nothing.
class _NumericInput extends StatefulWidget {
  const _NumericInput({
    super.key,
    required this.question,
    required this.initial,
    required this.strings,
    required this.enabled,
    required this.onChanged,
  });

  final Question question;
  final double? initial;
  final CareStrings strings;
  final bool enabled;
  final ValueChanged<AnswerValue> onChanged;

  @override
  State<_NumericInput> createState() => _NumericInputState();
}

class _NumericInputState extends State<_NumericInput> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial == null
        ? ''
        : formatQuestionnaireNumber(widget.initial!),
  );
  String? _error;

  Question get q => widget.question;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String? _problemText(NumericProblem p) => switch (p) {
    NumericProblem.belowMin => widget.strings.numberBelowMin(
      formatQuestionnaireNumber(q.minValue!),
    ),
    NumericProblem.aboveMax => widget.strings.numberAboveMax(
      formatQuestionnaireNumber(q.maxValue!),
    ),
    NumericProblem.offStep =>
      q.step == null
          ? widget.strings.t(CareText.qNumberInvalid)
          : widget.strings.numberStep(formatQuestionnaireNumber(q.step!)),
  };

  void _changed(String raw) {
    if (raw.trim().isEmpty) {
      setState(() => _error = null);
      widget.onChanged(AnswerValue.none);
      return;
    }
    final v = parseQuestionnaireNumber(raw);
    final problem = v == null ? null : numericProblem(q, v);
    setState(() {
      _error = v == null
          ? widget.strings.t(CareText.qNumberInvalid)
          : problem == null
          ? null
          : _problemText(problem);
    });
    widget.onChanged(
      v != null && problem == null ? AnswerValue(value: v) : AnswerValue.none,
    );
  }

  void _stepBy(int direction) {
    final step = q.step!;
    final current = parseQuestionnaireNumber(_c.text);
    var next = current == null ? (q.minValue ?? 0) : current + direction * step;
    if (q.minValue != null && next < q.minValue!) next = q.minValue!;
    if (q.maxValue != null && next > q.maxValue!) next = q.maxValue!;
    // Snap to the step grid so floating-point drift never makes it invalid.
    final base = q.minValue ?? 0;
    next = base + ((next - base) / step).roundToDouble() * step;
    _c.text = formatQuestionnaireNumber(next);
    _changed(_c.text);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final hasRange = q.minValue != null && q.maxValue != null;
    final decimal = q.step == null || q.step != q.step!.roundToDouble();
    final field = NeoInput(
      key: const Key('numeric-input'),
      controller: _c,
      enabled: widget.enabled,
      keyboardType: TextInputType.numberWithOptions(
        decimal: decimal,
        signed: q.minValue == null || q.minValue! < 0,
      ),
      error: _error,
      onChanged: _changed,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (q.step == null)
          field
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepButton(
                key: const Key('numeric-decrease'),
                label: s.t(CareText.qDecrease),
                icon: Icons.remove,
                onPressed: widget.enabled ? () => _stepBy(-1) : null,
              ),
              const SizedBox(width: 10),
              Expanded(child: field),
              const SizedBox(width: 10),
              _StepButton(
                key: const Key('numeric-increase'),
                label: s.t(CareText.qIncrease),
                icon: Icons.add,
                onPressed: widget.enabled ? () => _stepBy(1) : null,
              ),
            ],
          ),
        if (hasRange) ...[
          const SizedBox(height: 6),
          Text(
            s.numberRange(
              formatQuestionnaireNumber(q.minValue!),
              formatQuestionnaireNumber(q.maxValue!),
            ),
            key: const Key('numeric-range'),
            style: koiMutedStyle(12.5).copyWith(height: s.lineHeight),
          ),
        ],
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    excludeSemantics: true,
    child: NeoButton(
      variant: NeoButtonVariant.ghost,
      customPadding: const EdgeInsets.all(12),
      onPressed: onPressed,
      child: Icon(icon, size: 22),
    ),
  );
}
