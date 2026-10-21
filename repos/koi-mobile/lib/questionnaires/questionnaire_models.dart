import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show TextDirection;

// Patient-side questionnaire model (MOB-6). It follows contract v0.5.2
// (origin/feat/koi2-ui-overhaul f9ed940, repos/koi-backend/nextjs_app/
// contracts/v0.5.2/contracts.schema.json: PatientQuestionnaireDTO,
// Question, Option, ImageOption, LocalizedText, Answer; read with git show
// only) and the shared answer rules of src/lib/platform/answers.ts. The
// JSON mapping lives ONLY in questionnaire_wire.dart. These classes hold
// only what a patient may see: the published wording, the patient's own
// answers and the attempt lifecycle. Nothing about how answers are
// processed afterwards exists here (MOB1-33 scans this file).

/// Contract `Id`: `^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$`. Question, option,
/// asset, assignment, attempt and version ids. Ids are compared and sent
/// byte for byte, never trimmed or changed.
final RegExp questionnaireIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$',
);

bool isQuestionnaireId(Object? v) =>
    v is String && questionnaireIdPattern.hasMatch(v);

/// The seven v0.5.2 question types. Anything else (e.g. `numeric`) is
/// refused by the parser.
enum QuestionType {
  single('single_choice'),
  multi('multi_choice'),
  yesNo('yes_no'),
  likert('likert'),
  shortText('short_text'),
  imageSingle('image_single_choice'),
  imageMulti('image_multi_choice');

  const QuestionType(this.wire);
  final String wire;

  static QuestionType? fromWire(Object? v) =>
      values.where((t) => t.wire == v).firstOrNull;

  bool get isMulti => this == multi || this == imageMulti;
  bool get isImage => this == imageSingle || this == imageMulti;

  /// Answered with one option id.
  bool get isSingleOption =>
      this == single || this == likert || this == imageSingle;

  /// Has options.
  bool get hasOptions => isSingleOption || isMulti;
}

/// Contract `Locale`. A questionnaire lists one to three of them.
enum QuestionnaireLanguage {
  en('en'),
  ur('ur'),
  romanUr('ur-Latn');

  const QuestionnaireLanguage(this.wire);
  final String wire;

  static QuestionnaireLanguage? fromWire(Object? v) =>
      values.where((l) => l.wire == v).firstOrNull;

  /// Urdu script: shown right-to-left in Noto Nastaliq Urdu. Roman Urdu
  /// and English are left-to-right.
  bool get isUrduScript => this == ur;

  TextDirection get direction =>
      isUrduScript ? TextDirection.rtl : TextDirection.ltr;

  /// The language's own name, for the language chips.
  String get nativeName => switch (this) {
    en => 'English',
    ur => 'اردو',
    romanUr => 'Roman Urdu',
  };

  /// The web runner's fixed yes / no wording (QuestionFields.tsx).
  String get yes => switch (this) {
    en => 'Yes',
    ur => 'ہاں',
    romanUr => 'Haan',
  };

  String get no => switch (this) {
    en => 'No',
    ur => 'نہیں',
    romanUr => 'Nahin',
  };
}

/// Contract `LocalizedText`: published wording per locale, kept exactly as
/// sent (no trimming). Every locale the questionnaire lists has a text
/// (filled at parse time from the questionnaire's own locale order when
/// one is missing).
@immutable
class LocalizedText {
  const LocalizedText(this.values);

  final Map<QuestionnaireLanguage, String> values;

  /// [language], else English, else the first text there is.
  String resolve(QuestionnaireLanguage language) =>
      values[language] ??
      values[QuestionnaireLanguage.en] ??
      values.values.first;

  /// The same text with every one of [locales] filled, in that order of
  /// fallback.
  LocalizedText filledFor(List<QuestionnaireLanguage> locales) {
    final first = [
      for (final l in locales)
        if (values[l] != null) values[l]!,
    ].firstOrNull;
    if (first == null) return this;
    return LocalizedText(
      Map.unmodifiable({
        ...values,
        for (final l in locales) l: values[l] ?? first,
      }),
    );
  }
}

/// A question's or picture's asset: contract `AssetReference`. A picture is
/// shown only when all three fields match a bundled picture.
@immutable
class AssetReference {
  const AssetReference({
    required this.assetId,
    required this.version,
    required this.sha256,
  });

  final String assetId;
  final int version;
  final String sha256;

  @override
  bool operator ==(Object other) =>
      other is AssetReference &&
      other.assetId == assetId &&
      other.version == version &&
      other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(assetId, version, sha256);
}

/// A questionnaire the app must not show (unknown type, malformed, extra
/// keys). The screen shows a safe message instead, never a guess.
class UnsupportedQuestionnaireException implements Exception {
  const UnsupportedQuestionnaireException(this.reason);
  final String reason;

  @override
  String toString() => 'UnsupportedQuestionnaire($reason)';
}

/// Contract `Option` / `ImageOption` ([asset] only on picture questions).
@immutable
class QuestionnaireOption {
  const QuestionnaireOption({
    required this.id,
    required this.label,
    this.asset,
  });

  final String id;

  /// Exactly as published.
  final LocalizedText label;
  final AssetReference? asset;
}

/// Contract `Question` (one of seven types).
@immutable
class Question {
  const Question({
    required this.id,
    required this.type,
    required this.prompt,
    required this.required,
    this.options = const [],
    this.maxLength = maxTextLength,
    this.minSelections = 0,
    this.maxSelections = 20,
  });

  /// The contract's upper bound for `max_length`.
  static const int maxTextLength = 4000;

  final String id;
  final QuestionType type;
  final LocalizedText prompt;
  final bool required;

  /// In the published order (likert: as published).
  final List<QuestionnaireOption> options;

  /// short_text only.
  final int maxLength;

  /// multi_choice / image_multi_choice only.
  final int minSelections;
  final int maxSelections;

  QuestionnaireOption? option(String id) =>
      options.where((o) => o.id == id).firstOrNull;

  /// What answers.ts compares against (`max_selections ?? options.length`).
  int get selectionLimit =>
      maxSelections < options.length ? maxSelections : options.length;
}

/// The questionnaire of an open assignment (`PatientQuestionnaireDTO`).
@immutable
class PublishedQuestionnaire {
  const PublishedQuestionnaire({
    required this.versionId,
    required this.title,
    required this.locales,
    required this.questions,
  });

  /// Must equal the assignment's `questionnaire_version_id`.
  final String versionId;
  final LocalizedText title;

  /// In the published order (the web shows the first one by default).
  final List<QuestionnaireLanguage> locales;
  final List<Question> questions;

  Question? question(String id) =>
      questions.where((q) => q.id == id).firstOrNull;

  /// The language shown first: the app's language when this questionnaire
  /// has it, else English, else the first published locale.
  QuestionnaireLanguage defaultLanguage(String appLanguage) {
    final app = QuestionnaireLanguage.fromWire(appLanguage);
    if (app != null && locales.contains(app)) return app;
    if (locales.contains(QuestionnaireLanguage.en)) {
      return QuestionnaireLanguage.en;
    }
    return locales.first;
  }
}

/// What the patient entered for one question: chosen option ids, a yes /
/// no, or a text.
@immutable
class AnswerValue {
  const AnswerValue({this.optionIds = const [], this.text, this.yes});

  static const AnswerValue none = AnswerValue();

  final List<String> optionIds;
  final String? text;
  final bool? yes;
}

/// One answer, exactly the contract's `Answer`: `{question_id, type,
/// value}`. [value] is a String (single / likert / image single option id,
/// or short text), a List of option ids (multi) or a bool (yes_no).
@immutable
class Answer {
  const Answer({
    required this.questionId,
    required this.type,
    required this.value,
  });

  /// [input] as the answer to [q] (unsanitized).
  factory Answer.of(Question q, AnswerValue input) => Answer(
    questionId: q.id,
    type: q.type,
    value: switch (q.type) {
      QuestionType.yesNo => input.yes,
      QuestionType.shortText => input.text ?? '',
      QuestionType.multi ||
      QuestionType.imageMulti => List<String>.unmodifiable(input.optionIds),
      _ => input.optionIds.firstOrNull ?? '',
    },
  );

  final String questionId;
  final QuestionType type;
  final Object? value;

  List<String> get optionIds => switch (value) {
    final List<String> ids => ids,
    final String id when type.isSingleOption && id.isNotEmpty => [id],
    _ => const [],
  };

  String? get text => type == QuestionType.shortText && value is String
      ? value! as String
      : null;

  bool? get yes => value is bool ? value! as bool : null;

  bool get isEmpty => switch (value) {
    final List<String> ids => ids.isEmpty,
    final String s => s.isEmpty,
    final bool _ => false,
    _ => true,
  };

  AnswerValue get input =>
      AnswerValue(optionIds: optionIds, text: text, yes: yes);

  @override
  bool operator ==(Object other) =>
      other is Answer &&
      other.questionId == questionId &&
      other.type == type &&
      (value is List
          ? other.value is List &&
                listEquals(other.value! as List, value! as List)
          : other.value == value);

  @override
  int get hashCode => Object.hash(
    questionId,
    type,
    value is List ? Object.hashAll(value! as List) : value,
  );
}

/// The answer if it fits [q] structurally, else null: same type, known and
/// distinct option ids within the selection limit, text within
/// `max_length`. An empty entry is null (the answer is removed). A multi
/// selection below `min_selections` is KEPT here (it stays on this device);
/// [sendableAnswers] leaves it out of the save.
Answer? cleanAnswer(Question q, Answer a) {
  if (a.questionId != q.id || a.type != q.type) return null;
  final v = a.value;
  switch (q.type) {
    case QuestionType.yesNo:
      return v is bool ? a : null;
    case QuestionType.shortText:
      if (v is! String || v.isEmpty || v.length > q.maxLength) return null;
      return a;
    case QuestionType.multi || QuestionType.imageMulti:
      if (v is! List<String> || v.isEmpty) return null;
      if (v.toSet().length != v.length) return null;
      if (v.any((id) => q.option(id) == null)) return null;
      if (v.length > q.selectionLimit) return null;
      return a;
    default:
      return v is String && q.option(v) != null ? a : null;
  }
}

/// Keeps only answers that fit [q] (see [cleanAnswer]), keyed by question.
Map<String, Answer> sanitizeAnswers(
  PublishedQuestionnaire q,
  Map<String, Answer> answers,
) {
  final out = <String, Answer>{};
  for (final a in answers.values) {
    final question = q.question(a.questionId);
    if (question == null) continue;
    final clean = cleanAnswer(question, a);
    if (clean != null) out[question.id] = clean;
  }
  return out;
}

/// A multi selection that has some, but fewer than `min_selections`,
/// options (answers.ts refuses it in every save).
bool isBelowMinimum(Question q, Answer? a) =>
    q.type.isMulti &&
    a != null &&
    a.optionIds.isNotEmpty &&
    a.optionIds.length < q.minSelections;

/// Whether [q] may be left as it is when submitting (answers.ts with
/// `final = true`): required questions are answered (text not blank, at
/// least max(1, min) options) and no selection is below its minimum.
bool questionComplete(Question q, Answer? a) {
  if (isBelowMinimum(q, a)) return false;
  if (!q.required) return true;
  if (a == null || a.isEmpty) return false;
  return switch (q.type) {
    QuestionType.shortText => a.text!.trim().isNotEmpty,
    QuestionType.multi || QuestionType.imageMulti =>
      a.optionIds.length >= (q.minSelections > 1 ? q.minSelections : 1),
    _ => true,
  };
}

/// Questions that stop a submit, in questionnaire order.
List<String> missingRequired(
  PublishedQuestionnaire q,
  Map<String, Answer> answers,
) => [
  for (final question in q.questions)
    if (!questionComplete(question, answers[question.id])) question.id,
];

/// The answers an autosave sends, in questionnaire order: fitting answers
/// only, never a selection below its minimum.
List<Answer> sendableAnswers(
  PublishedQuestionnaire q,
  Map<String, Answer> answers,
) {
  final clean = sanitizeAnswers(q, answers);
  return [
    for (final question in q.questions)
      if (clean[question.id] case final a? when !isBelowMinimum(question, a)) a,
  ];
}

/// answers.ts `answerIssues`, rule for rule: an empty list means the server
/// accepts these answers (as a save, or with [isFinal] as a submit). Used
/// by the demo server and the tests; the app only ever sends
/// [sendableAnswers].
List<String> answerIssues(
  List<Question> questions,
  List<Answer> answers, {
  bool isFinal = false,
}) {
  final issues = <String>[];
  final seen = <String>{};
  for (final a in answers) {
    final q = questions.where((x) => x.id == a.questionId).firstOrNull;
    if (q == null || seen.contains(a.questionId) || q.type != a.type) {
      issues.add('unknown_or_duplicate');
      continue;
    }
    seen.add(a.questionId);
    final v = a.value;
    switch (q.type) {
      case QuestionType.yesNo:
        if (v is! bool) issues.add('yes_no');
      case QuestionType.shortText:
        if (v is! String ||
            v.length > q.maxLength ||
            (isFinal && q.required && v.trim().isEmpty)) {
          issues.add('text');
        }
      case QuestionType.multi || QuestionType.imageMulti:
        if (v is! List<String> ||
            v.toSet().length != v.length ||
            v.any((id) => q.option(id) == null) ||
            v.length > q.selectionLimit ||
            (v.isNotEmpty && v.length < q.minSelections) ||
            (isFinal &&
                q.required &&
                v.length < (q.minSelections > 1 ? q.minSelections : 1))) {
          issues.add('selection');
        }
      default:
        if (v is! String || q.option(v) == null) issues.add('option');
    }
  }
  if (isFinal && questions.any((q) => q.required && !seen.contains(q.id))) {
    issues.add('required');
  }
  return issues;
}

// ── Assignments and attempts (contract v0.5.2 lifecycle) ─────────────────

/// `PatientAssignmentDTO.state`.
enum AssignmentState {
  assigned('assigned'),
  inProgress('in_progress'),
  submitted('submitted');

  const AssignmentState(this.wire);
  final String wire;

  static AssignmentState? fromWire(Object? v) =>
      values.where((s) => s.wire == v).firstOrNull;
}

/// An assigned questionnaire in the patient's list
/// (`PatientAssignmentDTO`). [title] is the contract's LocalizedText
/// (`en`, `ur`, `ur-Latn`).
@immutable
class Assignment {
  const Assignment({
    required this.assignmentId,
    required this.attemptId,
    required this.versionId,
    required this.title,
    required this.state,
    this.dueAt,
  });

  final String assignmentId;
  final String attemptId;

  /// `questionnaire_version_id`: the immutable version this attempt is
  /// pinned to. Answers are never applied to another version.
  final String versionId;
  final Map<String, String> title;
  final AssignmentState state;
  final DateTime? dueAt;

  /// The title in [preferred] ('en' | 'ur'), else English, else any.
  String titleFor(String preferred) =>
      title[preferred] ??
      title['en'] ??
      title['ur-Latn'] ??
      title['ur'] ??
      title.values.first;
}

/// `not_started` → `in_progress`; submitted attempts are never returned,
/// only their acknowledgement.
enum AttemptStatus {
  notStarted('not_started'),
  inProgress('in_progress');

  const AttemptStatus(this.wire);
  final String wire;

  static AttemptStatus? fromWire(Object? v) =>
      values.where((s) => s.wire == v).firstOrNull;
}

/// The server's unfinished attempt (`PatientAttemptDTO`).
@immutable
class Attempt {
  const Attempt({
    required this.attemptId,
    required this.assignmentId,
    required this.versionId,
    required this.status,
    required this.revision,
    this.answers = const [],
  });

  final String attemptId;
  final String assignmentId;
  final String versionId;
  final AttemptStatus status;

  /// Bumped by every accepted autosave (including a Restart).
  final int revision;
  final List<Answer> answers;

  Map<String, Answer> get byQuestion => {
    for (final a in answers) a.questionId: a,
  };
}

/// The four-field submission acknowledgement (`PatientSubmitAckDTO`).
/// Nothing else exists on the patient side.
@immutable
class SubmitAck {
  const SubmitAck({
    required this.attemptId,
    required this.assignmentId,
    required this.submittedAt,
  });

  final String attemptId;
  final String assignmentId;
  final DateTime submittedAt;
}

/// `PatientAssignmentDetailDTO`: either the form to fill in, or only the
/// acknowledgement once submitted.
sealed class AssignmentDetail {
  const AssignmentDetail(this.assignment);
  final Assignment assignment;
}

final class OpenAssignment extends AssignmentDetail {
  const OpenAssignment(super.assignment, this.questionnaire, this.attempt);
  final PublishedQuestionnaire questionnaire;
  final Attempt attempt;
}

final class SubmittedAssignment extends AssignmentDetail {
  const SubmittedAssignment(super.assignment, this.acknowledgement);
  final SubmitAck acknowledgement;
}

/// `AutosaveAckDTO`.
@immutable
class AutosaveAck {
  const AutosaveAck({required this.attemptId, required this.revision});
  final String attemptId;
  final int revision;
}

/// One page of `PatientAssignmentListDTO`.
@immutable
class AssignmentPage {
  const AssignmentPage(this.items, this.nextCursor);
  final List<Assignment> items;
  final String? nextCursor;
}
