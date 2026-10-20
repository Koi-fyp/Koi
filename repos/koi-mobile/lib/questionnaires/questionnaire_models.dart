import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show TextDirection;

// Patient-side questionnaire model (MOB-3). It follows the AI track's
// QuestionnaireDraft (KOI-Psycholov contracts/schema/QuestionnaireDraft.json,
// ai-contracts-draft-0.2/0.3, MOBILE_HANDOFF.md §2) and the AI Answer shape
// (Submission.json). The JSON mapping lives ONLY in questionnaire_wire.dart.
// These classes hold only what a patient may see: the published wording,
// the patient's own answers and the attempt lifecycle. Nothing about how
// answers are processed afterwards exists here (MOB1-33 scans this file).

/// `^[A-Za-z0-9_-]{1,128}$`: question, option, source, asset and answer
/// ids. Ids are compared and sent byte for byte, never trimmed or changed.
final RegExp questionnaireIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

bool isQuestionnaireId(Object? v) =>
    v is String && questionnaireIdPattern.hasMatch(v);

enum QuestionType {
  single('single'),
  multi('multi'),
  yesNo('yes_no'),
  likert('likert'),
  freeText('free_text'),
  numeric('numeric'),
  imageSingle('image_single'),
  imageMulti('image_multi');

  const QuestionType(this.wire);
  final String wire;

  /// "rating" is the same type as likert (MOBILE_HANDOFF.md §2).
  static QuestionType? fromWire(Object? v) =>
      v == 'rating' ? likert : values.where((t) => t.wire == v).firstOrNull;

  bool get isMulti => this == multi || this == imageMulti;
  bool get isImage => this == imageSingle || this == imageMulti;

  /// Answered with `option_ids`.
  bool get isChoice => this != freeText && this != numeric;
}

/// One questionnaire is written in exactly one language.
enum QuestionnaireLanguage {
  en('en'),
  ur('ur'),
  romanUr('roman_ur');

  const QuestionnaireLanguage(this.wire);
  final String wire;

  static QuestionnaireLanguage? fromWire(Object? v) =>
      values.where((l) => l.wire == v).firstOrNull;

  /// Urdu script: shown in Noto Nastaliq Urdu.
  bool get isUrduScript => this == ur;
}

/// A questionnaire the app must not show (unknown type, malformed, not
/// published). The screen shows a safe message instead, never a guess.
class UnsupportedQuestionnaireException implements Exception {
  const UnsupportedQuestionnaireException(this.reason);
  final String reason;

  @override
  String toString() => 'UnsupportedQuestionnaire($reason)';
}

@immutable
class QuestionnaireOption {
  const QuestionnaireOption({
    required this.id,
    required this.label,
    this.assetId,
    this.visualDescription,
  });

  final String id;

  /// Exactly as published (fixed instruments are shown word for word).
  final String label;

  /// A bundled picture (`assets/questionnaire/<asset_id>.png`); never a URL.
  final String? assetId;

  /// Text shown when there is no known picture.
  final String? visualDescription;
}

@immutable
class Question {
  const Question({
    required this.id,
    required this.type,
    required this.text,
    this.helpText,
    this.required = true,
    this.options = const [],
    this.minValue,
    this.maxValue,
    this.step,
    this.assetId,
    this.visualDescription,
  });

  static const int maxTextLength = 4000;

  final String id;
  final QuestionType type;
  final String text;
  final String? helpText;
  final bool required;

  /// In the published order (likert: least → most as published).
  final List<QuestionnaireOption> options;

  /// numeric only.
  final double? minValue;
  final double? maxValue;
  final double? step;

  /// A picture for the question itself.
  final String? assetId;
  final String? visualDescription;

  QuestionnaireOption? option(String id) =>
      options.where((o) => o.id == id).firstOrNull;
}

/// Attribution for the published wording (WHO-5 and the mhGAP-derived
/// items need it: CC BY-NC-SA 3.0 IGO).
@immutable
class QuestionnaireSource {
  const QuestionnaireSource({
    required this.sourceId,
    this.citation,
    this.attributionText,
  });

  final String sourceId;
  final String? citation;
  final String? attributionText;

  bool get hasText => citation != null || attributionText != null;
}

/// A published, frozen questionnaire (`PublishedQuestionnaire.body`).
@immutable
class PublishedQuestionnaire {
  const PublishedQuestionnaire({
    required this.questionnaireId,
    required this.version,
    required this.title,
    required this.language,
    required this.rtl,
    required this.questions,
    this.description,
    this.sources = const [],
  });

  final String questionnaireId;
  final int version;
  final String title;
  final String? description;
  final QuestionnaireLanguage language;

  /// `true` exactly when the language is Urdu: the screen is laid out
  /// right-to-left. Roman Urdu and English are left-to-right.
  final bool rtl;
  final List<Question> questions;
  final List<QuestionnaireSource> sources;

  TextDirection get direction => rtl ? TextDirection.rtl : TextDirection.ltr;

  Question? question(String id) =>
      questions.where((q) => q.id == id).firstOrNull;
}

/// What the patient entered for one question, before it gets its stable
/// answer id: chosen option ids, a number or a text.
@immutable
class AnswerValue {
  const AnswerValue({this.optionIds = const [], this.value, this.text});

  static const AnswerValue none = AnswerValue();

  final List<String> optionIds;
  final double? value;
  final String? text;

  bool get isEmpty =>
      optionIds.isEmpty && value == null && (text == null || text!.isEmpty);
}

/// One answer, in the AI Answer shape: `{answer_id, question_id,
/// option_ids, value, text}`. [answerId] is a uuid v4 made on this device
/// once per question and kept across autosave, retry, resume and Restart.
@immutable
class Answer {
  const Answer({
    required this.answerId,
    required this.questionId,
    this.optionIds = const [],
    this.value,
    this.text,
  });

  final String answerId;
  final String questionId;
  final List<String> optionIds;
  final double? value;
  final String? text;

  bool get isEmpty =>
      optionIds.isEmpty && value == null && (text == null || text!.isEmpty);

  AnswerValue get input =>
      AnswerValue(optionIds: optionIds, value: value, text: text);

  @override
  bool operator ==(Object other) =>
      other is Answer &&
      other.answerId == answerId &&
      other.questionId == questionId &&
      listEquals(other.optionIds, optionIds) &&
      other.value == value &&
      other.text == text;

  @override
  int get hashCode =>
      Object.hash(answerId, questionId, Object.hashAll(optionIds), value, text);
}

/// Why a numeric entry is not accepted (null = fine).
enum NumericProblem { belowMin, aboveMax, offStep }

NumericProblem? numericProblem(Question q, double v) {
  if (!v.isFinite) return NumericProblem.offStep;
  final min = q.minValue;
  final max = q.maxValue;
  if (min != null && v < min) return NumericProblem.belowMin;
  if (max != null && v > max) return NumericProblem.aboveMax;
  final step = q.step;
  if (step != null && step > 0) {
    final k = (v - (min ?? 0)) / step;
    if ((k - k.roundToDouble()).abs() > 1e-9 * (k.abs() < 1 ? 1 : k.abs())) {
      return NumericProblem.offStep;
    }
  }
  return null;
}

/// Keeps only answers that fit [q]: known question ids, a valid answer id,
/// option ids that exist in that question (exactly as published), one
/// option for single-choice types, a number within the rules, text within
/// 4000 characters. Ids are never altered.
Map<String, Answer> sanitizeAnswers(
  PublishedQuestionnaire q,
  Map<String, Answer> answers,
) {
  final out = <String, Answer>{};
  for (final a in answers.values) {
    final question = q.question(a.questionId);
    if (question == null || !isQuestionnaireId(a.answerId)) continue;
    final clean = _clean(question, a);
    if (clean != null && !clean.isEmpty) out[question.id] = clean;
  }
  return out;
}

Answer? _clean(Question q, Answer a) {
  switch (q.type) {
    case QuestionType.freeText:
      final t = a.text;
      if (t == null || t.isEmpty || t.length > Question.maxTextLength) {
        return null;
      }
      return Answer(answerId: a.answerId, questionId: q.id, text: t);
    case QuestionType.numeric:
      final v = a.value;
      if (v == null || numericProblem(q, v) != null) return null;
      return Answer(answerId: a.answerId, questionId: q.id, value: v);
    default:
      final ids = <String>[];
      for (final id in a.optionIds) {
        if (q.option(id) != null && !ids.contains(id)) ids.add(id);
      }
      if (ids.isEmpty) return null;
      return Answer(
        answerId: a.answerId,
        questionId: q.id,
        optionIds: q.type.isMulti ? ids : [ids.first],
      );
  }
}

/// Required questions that are still unanswered, in questionnaire order.
List<String> missingRequired(
  PublishedQuestionnaire q,
  Map<String, Answer> answers,
) => [
  for (final question in q.questions)
    if (question.required && (answers[question.id]?.isEmpty ?? true))
      question.id,
];

/// Answers in questionnaire order (the order they are sent in).
List<Answer> orderedAnswers(
  PublishedQuestionnaire q,
  Map<String, Answer> answers,
) => [
  for (final question in q.questions)
    if (answers[question.id] != null) answers[question.id]!,
];

// ── Assignments and attempts (contract v0.5.1 lifecycle) ─────────────────

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
