import '../platform/platform_client.dart';
import 'questionnaire_models.dart';

// ALL JSON mapping of the patient questionnaire flow (MOB-6).
//
// REAL: contract v0.5.2 (origin/feat/koi2-ui-overhaul f9ed940,
// repos/koi-backend/nextjs_app/contracts/v0.5.2/contracts.schema.json, read
// with git show only): PatientAssignmentListDTO, PatientAssignmentDTO,
// PatientAssignmentDetailDTO (in progress | submitted),
// PatientQuestionnaireDTO, Question, Option, ImageOption, LocalizedText,
// PatientAttemptDTO, Answer, AutosaveRequest / AutosaveAckDTO,
// PatientSubmitRequest / PatientSubmitAckDTO. These are the shapes the
// web's end-to-end flow (answers → submit → evaluation → review) uses.
//
// STRICT, like the contract (`additionalProperties: false`): an object
// with a key the contract does not define is REFUSED, never half-read.
// A refused list item is skipped; a refused detail shows the safe "can't
// be shown" message. So nothing meant for the psychologist (scores,
// evaluations, reviews, job state) can be parsed, stored, shown, logged or
// sent back. The encoders write exactly the contract's keys. MOB1-33 scans
// this file.

/// Refuses [j] when it holds a key outside [allowed] or misses one of
/// [required].
void _keys(
  Map<String, Object?> j,
  String name, {
  required Set<String> allowed,
  Set<String> required = const {},
}) {
  for (final k in j.keys) {
    if (!allowed.contains(k)) throw FormatException('$name: unexpected key');
  }
  for (final k in required) {
    if (!j.containsKey(k)) throw FormatException('$name: missing $k');
  }
}

void _exactly(Map<String, Object?> j, String name, Set<String> keys) =>
    _keys(j, name, allowed: keys, required: keys);

// ── PatientQuestionnaireDTO ───────────────────────────────────────────────

/// Parses a `PatientQuestionnaireDTO`. Throws
/// [UnsupportedQuestionnaireException] (or FormatException) for anything
/// the app must not render: extra keys, unknown locale or type, duplicate
/// or malformed ids, empty wording, wrong option or selection counts.
PublishedQuestionnaire parsePatientQuestionnaire(Object? v) {
  final j = asJsonMap(v, 'questionnaire');
  _exactly(j, 'questionnaire', const {
    'version_id',
    'schema_version',
    'title',
    'locales',
    'questions',
  });
  if (j['schema_version'] != '0.5.0') {
    throw const UnsupportedQuestionnaireException('schema_version');
  }
  final locales = <QuestionnaireLanguage>[];
  for (final raw in asJsonList(j['locales'], 'locales')) {
    final l = QuestionnaireLanguage.fromWire(raw);
    if (l == null) throw const UnsupportedQuestionnaireException('locale');
    if (locales.contains(l)) throw const FormatException('duplicate locale');
    locales.add(l);
  }
  if (locales.isEmpty) throw const FormatException('no locale');
  final questions = [
    for (final q in asJsonList(j['questions'], 'questions'))
      _question(q, locales),
  ];
  if (questions.isEmpty || questions.length > 200) {
    throw const FormatException('question count');
  }
  if ({for (final q in questions) q.id}.length != questions.length) {
    throw const FormatException('duplicate question id');
  }
  return PublishedQuestionnaire(
    versionId: _id(j, 'version_id'),
    title: _localized(j['title'], 'title').filledFor(locales),
    locales: List.unmodifiable(locales),
    questions: List.unmodifiable(questions),
  );
}

const Set<String> _questionBase = {'id', 'prompt', 'required', 'type'};

Question _question(Object? v, List<QuestionnaireLanguage> locales) {
  final j = asJsonMap(v, 'question');
  final type = QuestionType.fromWire(j['type']);
  if (type == null) {
    throw const UnsupportedQuestionnaireException('question type');
  }
  final extra = switch (type) {
    QuestionType.yesNo => const <String>{},
    QuestionType.shortText => const {'max_length'},
    QuestionType.multi || QuestionType.imageMulti => const {
      'options',
      'min_selections',
      'max_selections',
    },
    _ => const {'options'},
  };
  _exactly(j, 'question', {..._questionBase, ...extra});
  final required = j['required'];
  if (required is! bool) throw const FormatException('Bad required');
  final options = <QuestionnaireOption>[];
  if (type.hasOptions) {
    for (final o in asJsonList(j['options'], 'options')) {
      options.add(_option(o, image: type.isImage, locales: locales));
    }
    final max = type == QuestionType.likert ? 11 : 20;
    if (options.length < 2 || options.length > max) {
      throw const FormatException('option count');
    }
    if ({for (final o in options) o.id}.length != options.length) {
      throw const FormatException('duplicate option id');
    }
  }
  var maxLength = Question.maxTextLength;
  if (type == QuestionType.shortText) {
    maxLength = _int(j, 'max_length', min: 1, max: Question.maxTextLength);
  }
  var minSel = 0;
  var maxSel = 20;
  if (type.isMulti) {
    minSel = _int(j, 'min_selections', min: 0, max: 20);
    maxSel = _int(j, 'max_selections', min: 1, max: 20);
    // A form nobody could ever complete is not shown.
    if (minSel > maxSel || minSel > options.length) {
      throw const UnsupportedQuestionnaireException('selection bounds');
    }
  }
  return Question(
    id: _id(j, 'id'),
    type: type,
    prompt: _localized(j['prompt'], 'prompt').filledFor(locales),
    required: required,
    options: List.unmodifiable(options),
    maxLength: maxLength,
    minSelections: minSel,
    maxSelections: maxSel,
  );
}

/// `Option` (`{id, label}`) or, on picture questions, `ImageOption`
/// (`{id, label, asset}`, asset required). A URL in place of an asset is an
/// unexpected key: refused.
QuestionnaireOption _option(
  Object? v, {
  required bool image,
  required List<QuestionnaireLanguage> locales,
}) {
  final j = asJsonMap(v, 'option');
  _exactly(
    j,
    'option',
    image ? const {'id', 'label', 'asset'} : const {'id', 'label'},
  );
  return QuestionnaireOption(
    id: _id(j, 'id'),
    label: _localized(j['label'], 'label').filledFor(locales),
    asset: image ? parseAssetReference(j['asset']) : null,
  );
}

/// `AssetReference {asset_id, version, sha256}`.
AssetReference parseAssetReference(Object? v) {
  final j = asJsonMap(v, 'asset');
  _exactly(j, 'asset', const {'asset_id', 'version', 'sha256'});
  final sha = j['sha256'];
  if (sha is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha)) {
    throw const FormatException('Bad sha256');
  }
  return AssetReference(
    assetId: _id(j, 'asset_id'),
    version: _int(j, 'version', min: 1),
    sha256: sha,
  );
}

/// `LocalizedText {en?, ur?, ur-Latn?}`: at least one, 1–4000 characters,
/// kept exactly as published (fixed wording is shown word for word).
LocalizedText _localized(Object? v, String name) {
  final j = asJsonMap(v, name);
  final out = <QuestionnaireLanguage, String>{};
  for (final e in j.entries) {
    final l = QuestionnaireLanguage.fromWire(e.key);
    final t = e.value;
    if (l == null) throw FormatException('$name: unexpected key');
    if (t is! String || t.isEmpty || t.length > 4000) {
      throw FormatException('Bad $name');
    }
    out[l] = t;
  }
  if (out.isEmpty) throw FormatException('Missing $name');
  return LocalizedText(Map.unmodifiable(out));
}

String _id(Map<String, Object?> j, String key) {
  final v = j[key];
  if (isQuestionnaireId(v)) return v! as String;
  throw FormatException('Bad $key');
}

int _int(Map<String, Object?> j, String key, {required int min, int? max}) {
  final v = j[key];
  if (v is! int || v < min || (max != null && v > max)) {
    throw FormatException('Bad $key');
  }
  return v;
}

bool _timestamp(Object? v) =>
    v is String && v.endsWith('Z') && DateTime.tryParse(v) != null;

// ── Answer ────────────────────────────────────────────────────────────────

/// `{question_id, type, value}`: exactly these keys. Ids are copied byte
/// for byte.
Map<String, Object?> encodeAnswer(Answer a) => {
  'question_id': a.questionId,
  'type': a.type.wire,
  'value': switch (a.value) {
    final List<String> ids => [...ids],
    final other => other,
  },
};

/// Parses one `Answer`. Throws FormatException for an extra key, an
/// unknown type or a value of the wrong shape.
Answer decodeAnswer(Object? v) {
  final j = asJsonMap(v, 'answer');
  _exactly(j, 'answer', const {'question_id', 'type', 'value'});
  final type = QuestionType.fromWire(j['type']);
  if (type == null) throw const FormatException('Bad answer type');
  final raw = j['value'];
  final Object value = switch (type) {
    QuestionType.yesNo when raw is bool => raw,
    QuestionType.shortText when raw is String && raw.length <= 4000 => raw,
    QuestionType.multi || QuestionType.imageMulti
        when raw is List &&
            raw.length <= 20 &&
            raw.every(isQuestionnaireId) &&
            raw.toSet().length == raw.length =>
      List<String>.unmodifiable(raw.cast<String>()),
    QuestionType.single ||
    QuestionType.likert ||
    QuestionType.imageSingle when isQuestionnaireId(raw) => raw! as String,
    _ => throw const FormatException('Bad answer value'),
  };
  return Answer(questionId: _id(j, 'question_id'), type: type, value: value);
}

// ── Envelopes ─────────────────────────────────────────────────────────────

/// `PatientAssignmentListDTO {items, next_cursor}`. An item that does not
/// parse (or carries an extra key) is skipped, never shown half-read.
AssignmentPage parseAssignmentPage(Object? v) {
  final j = asJsonMap(v, 'assignments');
  _exactly(j, 'assignments', const {'items', 'next_cursor'});
  final items = <Assignment>[];
  for (final raw in asJsonList(j['items'], 'items')) {
    try {
      items.add(parseAssignment(raw));
    } on FormatException {
      // skipped safely
    }
  }
  final next = j['next_cursor'];
  if (next != null && next is! String) {
    throw const FormatException('Bad next_cursor');
  }
  return AssignmentPage(
    List.unmodifiable(items),
    next is String && next.isNotEmpty ? next : null,
  );
}

/// `PatientAssignmentDTO`.
Assignment parseAssignment(Object? v) {
  final j = asJsonMap(v, 'assignment');
  _keys(
    j,
    'assignment',
    allowed: const {
      'id',
      'relationship_id',
      'organization_id',
      'questionnaire_version_id',
      'attempt_id',
      'title',
      'due_at',
      'state',
      'created_at',
    },
    required: const {
      'id',
      'relationship_id',
      'organization_id',
      'questionnaire_version_id',
      'attempt_id',
      'title',
      'state',
      'created_at',
    },
  );
  final state = AssignmentState.fromWire(j['state']);
  if (state == null) throw const FormatException('Bad state');
  _id(j, 'relationship_id');
  _id(j, 'organization_id');
  if (!_timestamp(j['created_at'])) throw const FormatException('created_at');
  final due = j['due_at'];
  if (due != null && !_timestamp(due)) throw const FormatException('due_at');
  final title = _localized(j['title'], 'title');
  return Assignment(
    assignmentId: _id(j, 'id'),
    attemptId: _id(j, 'attempt_id'),
    versionId: _id(j, 'questionnaire_version_id'),
    title: Map.unmodifiable({
      for (final e in title.values.entries) e.key.wire: e.value,
    }),
    state: state,
    dueAt: due is String ? DateTime.tryParse(due)?.toUtc() : null,
  );
}

/// `PatientAssignmentDetailDTO`: exactly `{assignment, questionnaire,
/// attempt}` while open, exactly `{assignment, acknowledgement}` once
/// submitted. A submitted detail that still carries the questionnaire or
/// the answers is refused.
AssignmentDetail parseAssignmentDetail(Object? v) {
  final j = asJsonMap(v, 'assignment detail');
  final assignment = parseAssignment(j['assignment']);
  if (assignment.state == AssignmentState.submitted) {
    _exactly(j, 'assignment detail', const {'assignment', 'acknowledgement'});
    return SubmittedAssignment(
      assignment,
      parseSubmitAck(j['acknowledgement']),
    );
  }
  _exactly(j, 'assignment detail', const {
    'assignment',
    'questionnaire',
    'attempt',
  });
  return OpenAssignment(
    assignment,
    parsePatientQuestionnaire(j['questionnaire']),
    parseAttempt(j['attempt']),
  );
}

/// `PatientAttemptDTO` (only `not_started` / `in_progress`; a submitted
/// attempt is never sent to the patient).
Attempt parseAttempt(Object? v) {
  final j = asJsonMap(v, 'attempt');
  _exactly(j, 'attempt', const {
    'id',
    'assignment_id',
    'patient_uid',
    'version_id',
    'status',
    'answers',
    'revision',
    'server_updated_at',
  });
  final status = AttemptStatus.fromWire(j['status']);
  if (status == null) throw const FormatException('Bad status');
  final revision = reqInt(j, 'revision');
  if (revision < 0) throw const FormatException('Bad revision');
  if (!_timestamp(j['server_updated_at'])) {
    throw const FormatException('server_updated_at');
  }
  final uid = j['patient_uid'];
  if (uid is! String || uid.isEmpty) throw const FormatException('uid');
  final answers = asJsonList(j['answers'], 'answers');
  if (answers.length > 200) throw const FormatException('answer count');
  return Attempt(
    attemptId: _id(j, 'id'),
    assignmentId: _id(j, 'assignment_id'),
    versionId: _id(j, 'version_id'),
    status: status,
    revision: revision,
    answers: List.unmodifiable([for (final a in answers) decodeAnswer(a)]),
  );
}

/// `AutosaveRequest {expected_revision, answers}`: exactly these keys. A
/// Restart is the same request with `answers: []`.
Map<String, Object?> encodeAutosave(int expectedRevision, List<Answer> a) => {
  'expected_revision': expectedRevision,
  'answers': [for (final x in a) encodeAnswer(x)],
};

/// `AutosaveAckDTO {attempt_id, revision, server_updated_at, status}`.
AutosaveAck parseAutosaveAck(Object? v) {
  final j = asJsonMap(v, 'autosave');
  _exactly(j, 'autosave', const {
    'attempt_id',
    'revision',
    'server_updated_at',
    'status',
  });
  if (j['status'] != 'in_progress') throw const FormatException('status');
  if (!_timestamp(j['server_updated_at'])) {
    throw const FormatException('server_updated_at');
  }
  return AutosaveAck(
    attemptId: _id(j, 'attempt_id'),
    revision: _int(j, 'revision', min: 1),
  );
}

/// `PatientSubmitRequest {expected_revision}`: the server submits the
/// answers it already saved.
Map<String, Object?> encodeSubmit(int expectedRevision) => {
  'expected_revision': expectedRevision,
};

/// `PatientSubmitAckDTO {attempt_id, assignment_id, submitted_at, status}`:
/// exactly these four keys.
SubmitAck parseSubmitAck(Object? v) {
  final j = asJsonMap(v, 'acknowledgement');
  _exactly(j, 'acknowledgement', const {
    'attempt_id',
    'assignment_id',
    'submitted_at',
    'status',
  });
  if (j['status'] != 'submitted') throw const FormatException('status');
  final raw = j['submitted_at'];
  if (!_timestamp(raw)) throw const FormatException('Bad submitted_at');
  return SubmitAck(
    attemptId: _id(j, 'attempt_id'),
    assignmentId: _id(j, 'assignment_id'),
    submittedAt: DateTime.parse(raw! as String).toUtc(),
  );
}
