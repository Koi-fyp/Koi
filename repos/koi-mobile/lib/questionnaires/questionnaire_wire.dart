import '../platform/platform_client.dart';
import 'questionnaire_models.dart';

// ALL JSON mapping of the patient questionnaire flow (MOB-3, option A).
//
// REAL (contract v0.5.1, origin/feat/web-1-professional-publishing f2b9c80,
// repos/koi-backend/nextjs_app/contracts/v0.5.1/contracts.schema.json, read
// with git show only): the envelopes. PatientAssignmentListDTO,
// PatientAssignmentDTO, PatientAssignmentDetailDTO (open | submitted),
// PatientAttemptDTO (minus its answer items), AutosaveRequest /
// AutosaveAckDTO, PatientSubmitRequest / PatientSubmitAckDTO.
//
// PROVISIONAL CONTRACT (KOI_MOB1_PROVISIONAL_CONTRACTS.md §3): two shapes
// come from the AI track (KOI-Psycholov MOBILE_HANDOFF.md §2,
// ai-contracts-draft-0.2) instead of v0.5.1:
// - the detail's `questionnaire` is a PublishedQuestionnaire whose `body`
//   is a QuestionnaireDraft (v0.5.1 has PatientQuestionnaireDTO);
// - every answer item is {answer_id, question_id, option_ids, value, text}
//   (v0.5.1 has {question_id, type, value}, additionalProperties false).
// A v0.5.1 server refuses these answers until the contracts agree. If the
// team picks the v0.5.1 shapes instead, only this file changes.
//
// Every parser reads a whitelist of keys; anything else the server sends
// (including fields meant for the psychologist) is dropped here and never
// stored, shown, logged or sent back. MOB1-33 scans this file.

// ── PROVISIONAL CONTRACT: PublishedQuestionnaire / QuestionnaireDraft ─────

/// Parses a PublishedQuestionnaire and its body. Throws
/// [UnsupportedQuestionnaireException] (or FormatException) for anything
/// the app must not render: not published, unknown language or type,
/// duplicate or malformed ids, empty wording, wrong option counts.
PublishedQuestionnaire parsePublishedQuestionnaire(Object? v) {
  final j = asJsonMap(v, 'questionnaire');
  if (j['status'] != 'published') {
    throw const UnsupportedQuestionnaireException('not published');
  }
  final version = j['version'];
  if (version is! int || version < 1) {
    throw const FormatException('Bad version');
  }
  final body = asJsonMap(j['body'], 'body');
  final language = QuestionnaireLanguage.fromWire(body['language']);
  if (language == null) {
    throw const UnsupportedQuestionnaireException('language');
  }
  final rtl = body['rtl'];
  // `rtl` is true exactly when the language is Urdu (MOBILE_HANDOFF.md §2).
  if (rtl is! bool || rtl != (language == QuestionnaireLanguage.ur)) {
    throw const UnsupportedQuestionnaireException('direction');
  }
  final questions = [
    for (final q in asJsonList(body['questions'], 'questions')) _question(q),
  ];
  final ids = {for (final q in questions) q.id};
  if (questions.isEmpty || questions.length > 100) {
    throw const FormatException('question count');
  }
  if (ids.length != questions.length) {
    throw const FormatException('duplicate question id');
  }
  return PublishedQuestionnaire(
    questionnaireId: _id(j, 'questionnaire_id'),
    version: version,
    title: _text(body, 'title'),
    description: _optText(body, 'description'),
    language: language,
    rtl: rtl,
    questions: List.unmodifiable(questions),
    sources: List.unmodifiable([
      for (final s in (body['sources'] as List?) ?? const []) ?_source(s),
    ]),
  );
}

Question _question(Object? v) {
  final j = asJsonMap(v, 'question');
  final type = QuestionType.fromWire(j['type']);
  if (type == null) {
    throw const UnsupportedQuestionnaireException('question type');
  }
  final options = [
    for (final o in (j['options'] as List?) ?? const []) _option(o),
  ];
  if ({for (final o in options) o.id}.length != options.length) {
    throw const FormatException('duplicate option id');
  }
  if (options.length > 12) throw const FormatException('option count');
  if (type.isChoice && options.isEmpty) {
    throw const FormatException('choice question without options');
  }
  if (type == QuestionType.yesNo && options.length != 2) {
    throw const FormatException('yes_no needs exactly 2 options');
  }
  if (type == QuestionType.likert &&
      (options.length < 3 || options.length > 7)) {
    throw const FormatException('likert needs 3-7 options');
  }
  final required = j['required'] ?? true;
  if (required is! bool) throw const FormatException('Bad required');
  final min = _optNum(j, 'min_value');
  final max = _optNum(j, 'max_value');
  final step = _optNum(j, 'step');
  if (min != null && max != null && min > max) {
    throw const FormatException('min_value > max_value');
  }
  if (step != null && step <= 0) throw const FormatException('Bad step');
  return Question(
    id: _id(j, 'question_id'),
    type: type,
    text: _text(j, 'text'),
    helpText: _optText(j, 'help_text'),
    required: required,
    options: type.isChoice ? List.unmodifiable(options) : const [],
    minValue: type == QuestionType.numeric ? min : null,
    maxValue: type == QuestionType.numeric ? max : null,
    step: type == QuestionType.numeric ? step : null,
    assetId: _assetId(j),
    visualDescription: _optText(j, 'visual_description'),
  );
}

QuestionnaireOption _option(Object? v) {
  final j = asJsonMap(v, 'option');
  return QuestionnaireOption(
    id: _id(j, 'option_id'),
    label: _text(j, 'label'),
    assetId: _assetId(j),
    visualDescription: _optText(j, 'visual_description'),
  );
}

QuestionnaireSource? _source(Object? v) {
  if (v is! Map) return null;
  final j = v.cast<String, Object?>();
  final id = j['source_id'];
  if (!isQuestionnaireId(id)) return null;
  return QuestionnaireSource(
    sourceId: id! as String,
    citation: _optText(j, 'citation'),
    attributionText: _optText(j, 'attribution_text'),
  );
}

/// An asset id that does not match the id pattern (e.g. a URL) is treated
/// as unknown: the picture is never loaded, its text is shown instead.
String? _assetId(Map<String, Object?> j) {
  final v = j['asset_id'];
  return isQuestionnaireId(v) ? v! as String : null;
}

String _id(Map<String, Object?> j, String key) {
  final v = j[key];
  if (isQuestionnaireId(v)) return v! as String;
  throw FormatException('Bad $key');
}

/// Published wording, kept exactly as sent (no trimming): fixed
/// instruments are shown word for word.
String _text(Map<String, Object?> j, String key) {
  final v = j[key];
  if (v is String && v.isNotEmpty) return v;
  throw FormatException('Missing $key');
}

String? _optText(Map<String, Object?> j, String key) {
  final v = j[key];
  return v is String && v.isNotEmpty ? v : null;
}

double? _optNum(Map<String, Object?> j, String key) {
  final v = j[key];
  if (v == null) return null;
  if (v is num && v.isFinite) return v.toDouble();
  throw FormatException('Bad $key');
}

// ── PROVISIONAL CONTRACT: Answer items ────────────────────────────────────

/// `{answer_id, question_id, option_ids, value, text}`: every key always
/// present (`[]` / null when unused). Ids are copied byte for byte.
Map<String, Object?> encodeAnswer(Answer a) => {
  'answer_id': a.answerId,
  'question_id': a.questionId,
  'option_ids': [...a.optionIds],
  'value': a.value,
  'text': a.text,
};

/// Null for anything malformed (it is then simply not shown).
Answer? decodeAnswer(Object? v) {
  if (v is! Map) return null;
  final j = v.cast<String, Object?>();
  final answerId = j['answer_id'];
  final questionId = j['question_id'];
  if (!isQuestionnaireId(answerId) || !isQuestionnaireId(questionId)) {
    return null;
  }
  final ids = j['option_ids'] ?? const <Object?>[];
  if (ids is! List || !ids.every(isQuestionnaireId)) return null;
  final value = j['value'];
  final text = j['text'];
  if (value != null && (value is! num || !value.isFinite)) return null;
  if (text != null && text is! String) return null;
  return Answer(
    answerId: answerId! as String,
    questionId: questionId! as String,
    optionIds: List.unmodifiable(ids.cast<String>()),
    value: (value as num?)?.toDouble(),
    text: text as String?,
  );
}

// ── REAL: contract v0.5.1 envelopes ───────────────────────────────────────

/// `PatientAssignmentListDTO {items, next_cursor}`. An item that does not
/// parse is skipped, never shown half-read.
AssignmentPage parseAssignmentPage(Object? v) {
  final j = asJsonMap(v, 'assignments');
  final items = <Assignment>[];
  for (final raw in asJsonList(j['items'], 'items')) {
    try {
      items.add(parseAssignment(raw));
    } on FormatException {
      // skipped safely
    }
  }
  final next = j['next_cursor'];
  return AssignmentPage(
    List.unmodifiable(items),
    next is String && next.isNotEmpty ? next : null,
  );
}

/// `PatientAssignmentDTO`.
Assignment parseAssignment(Object? v) {
  final j = asJsonMap(v, 'assignment');
  final state = AssignmentState.fromWire(j['state']);
  if (state == null) throw const FormatException('Bad state');
  final due = j['due_at'];
  return Assignment(
    assignmentId: _id(j, 'id'),
    attemptId: _id(j, 'attempt_id'),
    versionId: _id(j, 'questionnaire_version_id'),
    title: _localized(j['title']),
    state: state,
    dueAt: due is String ? DateTime.tryParse(due)?.toUtc() : null,
  );
}

/// LocalizedText `{en?, ur?, ur-Latn?}` with at least one entry.
Map<String, String> _localized(Object? v) {
  final j = asJsonMap(v, 'title');
  final out = <String, String>{
    for (final k in const ['en', 'ur', 'ur-Latn'])
      if (j[k] is String && (j[k]! as String).isNotEmpty) k: j[k]! as String,
  };
  if (out.isEmpty) throw const FormatException('Missing title');
  return Map.unmodifiable(out);
}

/// `PatientAssignmentDetailDTO`: `{assignment, questionnaire, attempt}`
/// while open, `{assignment, acknowledgement}` once submitted.
AssignmentDetail parseAssignmentDetail(Object? v) {
  final j = asJsonMap(v, 'assignment detail');
  final assignment = parseAssignment(j['assignment']);
  if (assignment.state == AssignmentState.submitted) {
    return SubmittedAssignment(
      assignment,
      parseSubmitAck(j['acknowledgement']),
    );
  }
  return OpenAssignment(
    assignment,
    parsePublishedQuestionnaire(j['questionnaire']),
    parseAttempt(j['attempt']),
  );
}

/// `PatientAttemptDTO` (answer items: PROVISIONAL, see [decodeAnswer]).
Attempt parseAttempt(Object? v) {
  final j = asJsonMap(v, 'attempt');
  final status = AttemptStatus.fromWire(j['status']);
  if (status == null) throw const FormatException('Bad status');
  final revision = reqInt(j, 'revision');
  if (revision < 0) throw const FormatException('Bad revision');
  return Attempt(
    attemptId: _id(j, 'id'),
    assignmentId: _id(j, 'assignment_id'),
    versionId: _id(j, 'version_id'),
    status: status,
    revision: revision,
    answers: List.unmodifiable([
      for (final a in asJsonList(j['answers'], 'answers')) ?decodeAnswer(a),
    ]),
  );
}

/// `AutosaveRequest {expected_revision, answers}`. A Restart is the same
/// request with `answers: []`.
Map<String, Object?> encodeAutosave(int expectedRevision, List<Answer> a) => {
  'expected_revision': expectedRevision,
  'answers': [for (final x in a) encodeAnswer(x)],
};

/// `AutosaveAckDTO {attempt_id, revision, server_updated_at, status}`.
AutosaveAck parseAutosaveAck(Object? v) {
  final j = asJsonMap(v, 'autosave');
  if (j['status'] != 'in_progress') throw const FormatException('status');
  return AutosaveAck(
    attemptId: _id(j, 'attempt_id'),
    revision: reqInt(j, 'revision'),
  );
}

/// `PatientSubmitRequest {expected_revision}`.
Map<String, Object?> encodeSubmit(int expectedRevision) => {
  'expected_revision': expectedRevision,
};

/// `PatientSubmitAckDTO {attempt_id, assignment_id, submitted_at, status}`.
SubmitAck parseSubmitAck(Object? v) {
  final j = asJsonMap(v, 'acknowledgement');
  if (j['status'] != 'submitted') throw const FormatException('status');
  final at = DateTime.tryParse(reqString(j, 'submitted_at'));
  if (at == null) throw const FormatException('Bad submitted_at');
  return SubmitAck(
    attemptId: _id(j, 'attempt_id'),
    assignmentId: _id(j, 'assignment_id'),
    submittedAt: at.toUtc(),
  );
}
