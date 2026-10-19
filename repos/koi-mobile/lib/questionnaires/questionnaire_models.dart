import 'package:flutter/painting.dart' show TextDirection;
import 'package:flutter/foundation.dart';

import '../platform/platform_client.dart';

// PROVISIONAL patient-side DTOs (no web contract yet; field names from
// KOI_MOBILE_TRACK_FINAL_REVIEWED.md §5-6, listed in
// KOI_MOB1_PROVISIONAL_CONTRACTS.md). Patient DTOs carry ONLY what a patient
// may see: the approved immutable questionnaire version, their own answers
// and the attempt lifecycle. Parsers read a whitelist of keys, so any other
// key the server might send is dropped and never stored, shown or logged.
// test/questionnaires/forbidden_fields_test.dart scans this file.

/// The only schema this app renders. A version with another schema is
/// refused (safe fallback), never guessed at.
const int supportedSchemaVersion = 1;

enum QuestionType {
  singleChoice('single_choice'),
  multiChoice('multi_choice'),
  yesNo('yes_no'),
  likert('likert'),
  shortText('short_text'),
  imageSingleChoice('image_single_choice'),
  imageMultiChoice('image_multi_choice');

  const QuestionType(this.wire);
  final String wire;

  static QuestionType? fromWire(Object? v) =>
      values.where((t) => t.wire == v).firstOrNull;

  bool get isMulti => this == multiChoice || this == imageMultiChoice;
  bool get isImage => this == imageSingleChoice || this == imageMultiChoice;
  bool get isText => this == shortText;
}

/// The locale a version is written in. Urdu script is right-to-left at the
/// question/answer block; Roman Urdu is left-to-right.
enum QuestionnaireLocale {
  en('en', TextDirection.ltr),
  ur('ur', TextDirection.rtl),
  romanUr('roman_ur', TextDirection.ltr);

  const QuestionnaireLocale(this.wire, this.direction);
  final String wire;
  final TextDirection direction;

  static QuestionnaireLocale? fromWire(Object? v) =>
      values.where((l) => l.wire == v).firstOrNull;
}

/// A version the app must not show: unapproved, unknown schema, unknown
/// question type, malformed. The screen shows a safe message instead.
class UnsupportedQuestionnaireException implements Exception {
  const UnsupportedQuestionnaireException(this.reason);
  final String reason;

  @override
  String toString() => 'UnsupportedQuestionnaire($reason)';
}

@immutable
class ChoiceOption {
  const ChoiceOption({required this.id, this.label, this.assetId});

  final String id;

  /// The approved wording; null when the translation is missing (the
  /// renderer shows a fallback, never other wording).
  final String? label;

  /// A bundled image from the shared asset manifest (image_* types).
  final String? assetId;

  factory ChoiceOption.fromJson(Object? v) {
    final j = asJsonMap(v, 'option');
    final label = j['label'];
    final asset = j['asset_id'];
    return ChoiceOption(
      id: reqString(j, 'id'),
      label: label is String && label.trim().isNotEmpty ? label : null,
      assetId: asset is String && asset.isNotEmpty ? asset : null,
    );
  }
}

@immutable
class Question {
  const Question({
    required this.id,
    required this.type,
    required this.required,
    this.prompt,
    this.options = const [],
    this.maxLength = defaultMaxLength,
  });

  static const int defaultMaxLength = 500;

  final String id;
  final QuestionType type;
  final bool required;

  /// Null when this locale's wording is missing.
  final String? prompt;
  final List<ChoiceOption> options;

  /// short_text only.
  final int maxLength;

  /// The wording (and every option label) exists in this version's locale.
  /// Image options may rely on the manifest's alt label instead.
  bool get hasWording =>
      prompt != null &&
      options.every(
        (o) => o.label != null || (type.isImage && o.assetId != null),
      );

  bool hasOption(String id) => options.any((o) => o.id == id);

  factory Question.fromJson(Object? v) {
    final j = asJsonMap(v, 'question');
    final type = QuestionType.fromWire(j['type']);
    if (type == null) {
      throw const UnsupportedQuestionnaireException('question type');
    }
    final prompt = j['prompt'];
    final options = [
      for (final o in (j['options'] as List?) ?? const [])
        ChoiceOption.fromJson(o),
    ];
    final ids = {for (final o in options) o.id};
    if (ids.length != options.length) {
      throw const FormatException('duplicate option id');
    }
    if (!type.isText && options.isEmpty) {
      throw const FormatException('choice question without options');
    }
    if (type.isImage && options.any((o) => o.assetId == null)) {
      throw const FormatException('image option without asset_id');
    }
    final max = j['max_length'];
    return Question(
      id: reqString(j, 'id'),
      type: type,
      required: j['required'] == true,
      prompt: prompt is String && prompt.trim().isNotEmpty ? prompt : null,
      options: List.unmodifiable(options),
      maxLength: max is int && max > 0 ? max : defaultMaxLength,
    );
  }
}

/// An APPROVED, IMMUTABLE questionnaire version, pinned by [versionId].
@immutable
class QuestionnaireVersion {
  const QuestionnaireVersion({
    required this.versionId,
    required this.questionnaireId,
    required this.locale,
    required this.title,
    required this.questions,
    this.instructions,
    this.assetManifestVersion,
  });

  final String versionId;
  final String questionnaireId;
  final QuestionnaireLocale locale;
  final String title;
  final String? instructions;

  /// Which shared asset manifest the image ids refer to.
  final String? assetManifestVersion;

  /// In the server's order (the ordered question ids).
  final List<Question> questions;

  Question? question(String id) =>
      questions.where((q) => q.id == id).firstOrNull;

  factory QuestionnaireVersion.fromJson(Object? v) {
    final j = asJsonMap(v, 'questionnaire version');
    if (j['approved'] != true) {
      // Never render a draft / unapproved version to a patient.
      throw const UnsupportedQuestionnaireException('not approved');
    }
    if (j['schema_version'] != supportedSchemaVersion) {
      throw const UnsupportedQuestionnaireException('schema version');
    }
    final locale = QuestionnaireLocale.fromWire(j['locale']);
    if (locale == null) {
      throw const UnsupportedQuestionnaireException('locale');
    }
    final questions = [
      for (final q in asJsonList(j['questions'], 'questions'))
        Question.fromJson(q),
    ];
    final ids = {for (final q in questions) q.id};
    if (questions.isEmpty || ids.length != questions.length) {
      throw const FormatException('question ids');
    }
    final manifest = j['asset_manifest_version'];
    final instructions = j['instructions'];
    return QuestionnaireVersion(
      versionId: reqString(j, 'version_id'),
      questionnaireId: reqString(j, 'questionnaire_id'),
      locale: locale,
      title: reqString(j, 'title'),
      instructions: instructions is String && instructions.trim().isNotEmpty
          ? instructions
          : null,
      assetManifestVersion: manifest is String ? manifest : null,
      questions: List.unmodifiable(questions),
    );
  }
}

/// One answer: chosen option ids (choice types) or text (short_text).
@immutable
class Answer {
  const Answer({this.optionIds = const [], this.text});

  final List<String> optionIds;
  final String? text;

  bool get isEmpty =>
      optionIds.isEmpty && (text == null || text!.trim().isEmpty);

  /// Whitelisted wire form: `{"option_ids": [...]}` or `{"text": "..."}`.
  Map<String, Object?> toJson() => {
    if (optionIds.isNotEmpty) 'option_ids': optionIds,
    if (text != null) 'text': text,
  };

  static Answer? fromJson(Object? v) {
    if (v is! Map) return null;
    final ids = v['option_ids'];
    final text = v['text'];
    return Answer(
      optionIds: [
        if (ids is List)
          for (final i in ids)
            if (i is String) i,
      ],
      text: text is String ? text : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Answer &&
      listEquals(other.optionIds, optionIds) &&
      other.text == text;

  @override
  int get hashCode => Object.hash(Object.hashAll(optionIds), text);
}

/// Keeps only answers that fit [version]: known question ids, option ids
/// that exist in that question, one option for single-choice types, text
/// within max length. Answers are NEVER carried across versions.
Map<String, Answer> sanitizeAnswers(
  QuestionnaireVersion version,
  Map<String, Answer> answers,
) {
  final out = <String, Answer>{};
  for (final e in answers.entries) {
    final q = version.question(e.key);
    if (q == null) continue;
    final a = e.value;
    if (q.type.isText) {
      final t = a.text;
      if (t != null && t.length <= q.maxLength) out[q.id] = Answer(text: t);
      continue;
    }
    final ids = [
      for (final id in a.optionIds)
        if (q.hasOption(id)) id,
    ];
    if (ids.isEmpty) continue;
    out[q.id] = Answer(
      optionIds: q.type.isMulti ? ids.toSet().toList() : [ids.first],
    );
  }
  return out;
}

/// Question ids that block submission: required + unanswered, or required
/// with no wording in this locale (cannot be answered safely).
List<String> missingRequired(
  QuestionnaireVersion version,
  Map<String, Answer> answers,
) => [
  for (final q in version.questions)
    if (q.required && (!q.hasWording || (answers[q.id]?.isEmpty ?? true))) q.id,
];

/// not_started → in_progress → submitted (terminal).
enum AttemptStatus {
  notStarted('not_started'),
  inProgress('in_progress'),
  submitted('submitted');

  const AttemptStatus(this.wire);
  final String wire;

  static AttemptStatus fromWire(Object? v) =>
      values.where((s) => s.wire == v).firstOrNull ??
      (throw const FormatException('attempt status'));
}

/// The server's attempt: lifecycle, revision and the patient's own answers.
@immutable
class Attempt {
  const Attempt({
    required this.attemptId,
    required this.assignmentId,
    required this.versionId,
    required this.status,
    required this.revision,
    this.answers = const {},
    this.submittedAt,
  });

  final String attemptId;
  final String assignmentId;
  final String versionId;
  final AttemptStatus status;

  /// Monotonically increasing; every accepted autosave / restart bumps it.
  final int revision;
  final Map<String, Answer> answers;
  final DateTime? submittedAt;

  factory Attempt.fromJson(Object? v) {
    final j = asJsonMap(v, 'attempt');
    final raw = j['answers'];
    final submitted = j['submitted_at'];
    return Attempt(
      attemptId: reqString(j, 'attempt_id'),
      assignmentId: reqString(j, 'assignment_id'),
      versionId: reqString(j, 'version_id'),
      status: AttemptStatus.fromWire(j['status']),
      revision: reqInt(j, 'revision'),
      answers: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.key is String && Answer.fromJson(e.value) != null)
              e.key as String: Answer.fromJson(e.value)!,
      },
      submittedAt: submitted is String ? DateTime.tryParse(submitted) : null,
    );
  }
}

/// An assigned questionnaire in the patient's list.
@immutable
class Assignment {
  const Assignment({
    required this.assignmentId,
    required this.attemptId,
    required this.versionId,
    required this.title,
    required this.status,
    this.dueAt,
  });

  final String assignmentId;
  final String attemptId;
  final String versionId;
  final String title;
  final AttemptStatus status;
  final DateTime? dueAt;

  factory Assignment.fromJson(Object? v) {
    final j = asJsonMap(v, 'assignment');
    final due = j['due_at'];
    return Assignment(
      assignmentId: reqString(j, 'assignment_id'),
      attemptId: reqString(j, 'attempt_id'),
      versionId: reqString(j, 'version_id'),
      title: reqString(j, 'title'),
      status: AttemptStatus.fromWire(j['status']),
      dueAt: due is String ? DateTime.tryParse(due) : null,
    );
  }
}

/// The server accepted an autosave.
@immutable
class DraftAck {
  const DraftAck({required this.revision});
  final int revision;
}

/// The submission acknowledgement: that it was received, and when. Nothing
/// else exists on the patient side.
@immutable
class SubmitAck {
  const SubmitAck({required this.attemptId, this.submittedAt});
  final String attemptId;
  final DateTime? submittedAt;

  factory SubmitAck.fromJson(Object? v) {
    final j = asJsonMap(v, 'submission');
    if (j['status'] != AttemptStatus.submitted.wire) {
      throw const FormatException('not submitted');
    }
    final at = j['submitted_at'];
    return SubmitAck(
      attemptId: reqString(j, 'attempt_id'),
      submittedAt: at is String ? DateTime.tryParse(at) : null,
    );
  }
}
