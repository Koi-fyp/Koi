import 'package:flutter/material.dart';

import '../account/account_widgets.dart';
import '../theme/koi_colors.dart';
import '../theme/koi_radii.dart';
import '../theme/koi_shadows.dart';
import '../widgets/koi_loader.dart';
import '../widgets/neo_input.dart';
import 'asset_manifest.dart';
import 'questionnaire_models.dart';

/// Text style for questionnaire wording. Urdu script gets a taller line
/// (Nastaliq) and falls back to the SYSTEM Urdu font for its glyphs: no new
/// font family is added (decided 2026-10-19); the family stays the theme's.
TextStyle questionnaireTextStyle(
  QuestionnaireLocale locale, {
  double size = 16,
  FontWeight weight = FontWeight.w400,
}) => koiBodyStyle(
  size: size,
  weight: weight,
).copyWith(height: locale == QuestionnaireLocale.ur ? 1.9 : 1.5);

/// Shown instead of a question whose wording is missing in this locale:
/// the instrument wording is never replaced or translated in the app.
const String missingWordingText =
    'This question is not available in your language yet. Please let your '
    'psychologist know.';

/// One question of an approved version. The whole question/answer block
/// takes the version's direction (Urdu right-to-left, Roman Urdu and
/// English left-to-right).
class QuestionView extends StatelessWidget {
  const QuestionView({
    super.key,
    required this.question,
    required this.locale,
    required this.answer,
    required this.onChanged,
    required this.manifest,
    this.manifestVersion,
    this.enabled = true,
  });

  final Question question;
  final QuestionnaireLocale locale;
  final Answer? answer;
  final ValueChanged<Answer> onChanged;
  final QuestionnaireAssetManifest manifest;
  final String? manifestVersion;
  final bool enabled;

  void _toggle(String optionId) {
    final current = answer?.optionIds ?? const <String>[];
    if (question.type.isMulti) {
      onChanged(
        Answer(
          optionIds: current.contains(optionId)
              ? [
                  for (final id in current)
                    if (id != optionId) id,
                ]
              : [...current, optionId],
        ),
      );
    } else {
      onChanged(Answer(optionIds: [optionId]));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!question.hasWording) {
      return KoiNoticeCard(
        key: const Key('question-missing-wording'),
        message: missingWordingText,
      );
    }
    final selected = answer?.optionIds ?? const <String>[];
    return Directionality(
      textDirection: locale.direction,
      child: Column(
        key: Key('question-${question.id}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              question.prompt!,
              key: const Key('question-prompt'),
              style: questionnaireTextStyle(
                locale,
                size: 19,
                weight: FontWeight.w700,
              ),
            ),
          ),
          if (!question.required) Text('(optional)', style: koiMutedStyle(13)),
          const SizedBox(height: 16),
          if (question.type.isText)
            _ShortText(
              key: ValueKey('text-${question.id}'),
              initial: answer?.text ?? '',
              maxLength: question.maxLength,
              enabled: enabled,
              onChanged: (t) => onChanged(Answer(text: t)),
            )
          else if (question.type.isImage)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final o in question.options)
                  _ImageTile(
                    option: o,
                    locale: locale,
                    asset: manifest.resolve(
                      o.assetId!,
                      forManifestVersion: manifestVersion,
                    ),
                    selected: selected.contains(o.id),
                    multi: question.type.isMulti,
                    onTap: enabled ? () => _toggle(o.id) : null,
                  ),
              ],
            )
          else
            for (final o in question.options)
              _ChoiceTile(
                option: o,
                locale: locale,
                selected: selected.contains(o.id),
                multi: question.type.isMulti,
                onTap: enabled ? () => _toggle(o.id) : null,
              ),
        ],
      ),
    );
  }
}

/// A selectable answer row: white Neo tile, yellow + hard shadow when
/// chosen. Radio semantics for single choice, checkbox for multi.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.option,
    required this.locale,
    required this.selected,
    required this.multi,
    required this.onTap,
  });

  final ChoiceOption option;
  final QuestionnaireLocale locale;
  final bool selected;
  final bool multi;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final reduce = koiReduceMotion(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        key: Key('option-${option.id}'),
        inMutuallyExclusiveGroup: !multi,
        checked: selected,
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
            decoration: BoxDecoration(
              color: selected ? KoiColors.neoYellow : KoiColors.neoWhite,
              border: Border.all(width: 2.5),
              borderRadius: KoiRadii.inputAll,
              boxShadow: selected ? KoiShadows.neoMd : KoiShadows.neoSm,
            ),
            child: Row(
              children: [
                _Mark(selected: selected, multi: multi),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    option.label ?? '',
                    style: questionnaireTextStyle(
                      locale,
                      weight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
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

/// A picture option from the bundled manifest. Unknown asset id (or a
/// different manifest version) → an accessible text fallback with the
/// option's label: never another picture, never altered wording.
class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.option,
    required this.locale,
    required this.asset,
    required this.selected,
    required this.multi,
    required this.onTap,
  });

  final ChoiceOption option;
  final QuestionnaireLocale locale;
  final QuestionnaireAsset? asset;
  final bool selected;
  final bool multi;
  final VoidCallback? onTap;

  static const double side = 132;
  static const String unavailable = 'Picture unavailable';

  @override
  Widget build(BuildContext context) {
    final a = asset;
    final label = option.label ?? a?.altFor(locale) ?? unavailable;
    final fallback = Center(
      key: Key('image-fallback-${option.id}'),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          unavailable,
          textAlign: TextAlign.center,
          style: koiMutedStyle(12.5),
        ),
      ),
    );
    return Semantics(
      key: Key('option-${option.id}'),
      inMutuallyExclusiveGroup: !multi,
      checked: selected,
      enabled: onTap != null,
      image: a != null,
      label: a == null ? '$label. $unavailable' : label,
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
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: questionnaireTextStyle(locale, size: 13),
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

class _ShortText extends StatefulWidget {
  const _ShortText({
    super.key,
    required this.initial,
    required this.maxLength,
    required this.enabled,
    required this.onChanged,
  });

  final String initial;
  final int maxLength;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_ShortText> createState() => _ShortTextState();
}

class _ShortTextState extends State<_ShortText> {
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
        key: const Key('short-text'),
        controller: _c,
        multiline: true,
        enabled: widget.enabled,
        onChanged: (t) {
          if (t.length > widget.maxLength) {
            _c.text = t.substring(0, widget.maxLength);
            _c.selection = TextSelection.collapsed(offset: widget.maxLength);
          }
          widget.onChanged(_c.text);
        },
      ),
      const SizedBox(height: 4),
      Text(
        '${_c.text.length} / ${widget.maxLength}',
        textAlign: TextAlign.end,
        style: koiMutedStyle(12),
      ),
    ],
  );
}
