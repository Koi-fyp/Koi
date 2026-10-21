import 'dart:async';

import 'package:flutter/foundation.dart';

import '../chat/conversation_service.dart' show uuidV4;
import '../platform/platform_client.dart';
import 'draft_store.dart';
import 'questionnaire_api.dart';
import 'questionnaire_models.dart';

enum AttemptPhase {
  loading,

  /// Could not load (offline before the form loaded, not found, forbidden,
  /// unsupported questionnaire). [AttemptController.loadError] says which.
  unavailable,
  answering,

  /// Submit is in flight (or being confirmed after a timeout).
  submitting,

  /// Terminal. Shows only "Response submitted" (+ time).
  submitted,
}

/// The autosave indicator.
enum SaveStatus {
  idle,
  saving,
  saved,

  /// No connection: kept on this device (and in memory), sent when the
  /// connection is back. Never shown as being on another device.
  offline,

  /// The server refused this save (not a connection problem). The answers
  /// stay editable; the next change tries again.
  notSaved,

  /// The server has a newer revision: autosave stops until the user picks
  /// a safe resolution.
  conflict,
}

enum AttemptLoadError { offline, notFound, forbidden, unsupported, other }

/// Why the last submit did not complete (the form stays as it was).
enum SubmitProblem {
  /// Required questions are unanswered; [AttemptController.missing] lists them.
  incomplete,

  /// No connection: submitting is online-only.
  offline,

  /// The outcome could not be confirmed; tapping Submit again re-uses the
  /// same idempotency key, so it can never create a second submission.
  unconfirmed,
  conflict,

  /// The server wants a recent sign-in (contract: submit needs auth_time
  /// within five minutes). The screen asks for the password and submits
  /// again with the same key.
  reauth,
  other,
}

/// One patient's attempt: load → answer (debounced autosave, revision
/// compare-and-set) → submit (idempotent) → submitted (terminal).
///
/// Contract v0.5.2 flow (REAL paths): `GET /patient/assignments/{id}`,
/// `PATCH /patient/attempts/{id}` (Restart = the same PATCH with no
/// answers), `POST /patient/attempts/{id}/submit`. Rules:
/// - answers travel as the contract's `{question_id, type, value}` only;
///   a multi selection below its minimum stays on this device until valid;
/// - a retry of the same save reuses its Idempotency-Key; a different
///   save gets a new one;
/// - a newer remote revision is NEVER overwritten silently: the state goes
///   to [SaveStatus.conflict] and the user chooses;
/// - answers are never applied to another questionnaire version;
/// - once submitted (here, elsewhere, or reported by the server), the
///   attempt is locked and pending local edits are discarded.
///
/// Never logs answers.
class AttemptController extends ChangeNotifier {
  AttemptController({
    required this.uid,
    required this.assignment,
    required this.api,
    required this.drafts,
    this.onlineChanges,
    this.debounce = const Duration(milliseconds: 800),
    String Function()? newKey,
  }) : _newKey = newKey ?? uuidV4 {
    _onlineSub = onlineChanges?.where((o) => o).listen((_) {
      if (_saveStatus == SaveStatus.offline) unawaited(_flush());
    });
  }

  final String uid;
  final Assignment assignment;
  final QuestionnaireApi api;
  final DraftRepository drafts;
  final Stream<bool>? onlineChanges;
  final Duration debounce;
  final String Function() _newKey;

  StreamSubscription<bool>? _onlineSub;
  Timer? _timer;
  bool _disposed = false;

  AttemptPhase _phase = AttemptPhase.loading;
  AttemptLoadError? _loadError;
  PublishedQuestionnaire? _questionnaire;
  Map<String, Answer> _answers = {};

  int _serverRevision = 0;
  bool _dirty = false;

  /// Bumped on every local change; a save that finishes for an older
  /// mutation leaves the draft dirty.
  int _mutation = 0;

  /// The key of the save for [_saveKeyMutation]: reused when that same
  /// save is retried, replaced as soon as the answers change.
  String? _saveKey;
  int? _saveKeyMutation;
  SaveStatus _saveStatus = SaveStatus.idle;
  int? _remoteRevision;

  /// The answers this device still holds while in conflict.
  Map<String, Answer>? _conflictLocal;
  String? _idempotencyKey;
  SubmitProblem? _submitProblem;
  List<String> _missing = const [];
  DateTime? _submittedAt;
  int _index = 0;
  Future<void>? _saving;

  AttemptPhase get phase => _phase;
  AttemptLoadError? get loadError => _loadError;
  PublishedQuestionnaire? get questionnaire => _questionnaire;
  Map<String, Answer> get answers => Map.unmodifiable(_answers);
  SaveStatus get saveStatus => _saveStatus;
  int get serverRevision => _serverRevision;
  int? get remoteRevision => _remoteRevision;
  SubmitProblem? get submitProblem => _submitProblem;
  List<String> get missing => _missing;
  DateTime? get submittedAt => _submittedAt;
  int get index => _index;
  bool get locked => _phase == AttemptPhase.submitted;
  bool get hasUnsyncedChanges => _dirty;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Load / resume ──────────────────────────────────────────────────────

  Future<void> load() async {
    _phase = AttemptPhase.loading;
    _loadError = null;
    _notify();
    try {
      final detail = await api.detail(assignment.assignmentId);
      switch (detail) {
        case SubmittedAssignment(:final acknowledgement):
          await _lock(acknowledgement.submittedAt);
        case OpenAssignment(:final questionnaire, :final attempt):
          if (attempt.versionId != assignment.versionId ||
              questionnaire.versionId != assignment.versionId ||
              detail.assignment.versionId != assignment.versionId ||
              attempt.attemptId != assignment.attemptId) {
            // Never show or merge answers across versions.
            throw const UnsupportedQuestionnaireException('version mismatch');
          }
          _questionnaire = questionnaire;
          await _adopt(
            attempt,
            local: await drafts.load(uid, assignment.attemptId),
          );
      }
    } catch (e) {
      _phase = AttemptPhase.unavailable;
      _loadError = switch (e) {
        PlatformException(code: PlatformErrorCode.network) ||
        PlatformException(
          code: PlatformErrorCode.timeout,
        ) => AttemptLoadError.offline,
        PlatformException(code: PlatformErrorCode.notFound) =>
          AttemptLoadError.notFound,
        PlatformException(code: PlatformErrorCode.forbidden) =>
          AttemptLoadError.forbidden,
        UnsupportedQuestionnaireException() ||
        FormatException() => AttemptLoadError.unsupported,
        _ => AttemptLoadError.other,
      };
      debugPrint('[KOI] questionnaire not loaded (${_loadError!.name})');
    }
    _notify();
  }

  /// Applies the server's attempt, deciding what to do with this device's
  /// draft. The server state + revision always come first.
  Future<void> _adopt(Attempt attempt, {LocalDraft? local}) async {
    final q = _questionnaire!;
    _serverRevision = attempt.revision;
    final server = sanitizeAnswers(q, attempt.byQuestion);
    final mine = local != null && local.versionId == assignment.versionId
        ? local
        : null;
    if (mine != null) {
      _idempotencyKey = mine.idempotencyKey;
    }
    if (mine != null && mine.dirty) {
      final edits = sanitizeAnswers(q, mine.answers);
      if (mine.baseRevision == attempt.revision) {
        // Nothing newer remotely: this device's edits continue.
        _answers = edits;
        _dirty = true;
        _phase = AttemptPhase.answering;
        _schedule(Duration.zero);
        return;
      }
      if (!_sameValues(edits, server)) {
        // A newer remote revision: never overwrite it blindly.
        _answers = server;
        _conflictLocal = edits;
        _remoteRevision = attempt.revision;
        _saveStatus = SaveStatus.conflict;
        _phase = AttemptPhase.answering;
        return;
      }
    }
    _answers = server;
    _dirty = false;
    _saveStatus = SaveStatus.idle;
    _phase = AttemptPhase.answering;
    await _writeLocal();
  }

  static bool _sameValues(Map<String, Answer> a, Map<String, Answer> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  Future<void> _writeLocal() async {
    if (_questionnaire == null || locked) return;
    try {
      await drafts.save(
        uid,
        LocalDraft(
          attemptId: assignment.attemptId,
          versionId: assignment.versionId,
          baseRevision: _serverRevision,
          dirty: _dirty,
          answers: _answers,
          idempotencyKey: _idempotencyKey,
        ),
      );
    } catch (e) {
      debugPrint('[KOI] questionnaire draft not stored (${e.runtimeType})');
    }
  }

  Future<void> _lock(DateTime? at) async {
    _timer?.cancel();
    _phase = AttemptPhase.submitted;
    _submittedAt = at;
    _dirty = false;
    _conflictLocal = null;
    _saveStatus = SaveStatus.idle;
    await drafts.delete(uid, assignment.attemptId);
  }

  // ── Answering ──────────────────────────────────────────────────────────

  void goTo(int i) {
    final q = _questionnaire;
    if (q == null) return;
    _index = i.clamp(0, q.questions.length - 1);
    _notify();
  }

  /// Records what the patient entered for [questionId]. Ignored once
  /// locked or while in conflict (the user must resolve first, so nothing
  /// is lost or merged). An empty or invalid entry removes the answer.
  void setAnswer(String questionId, AnswerValue value) {
    final q = _questionnaire;
    if (q == null || _phase != AttemptPhase.answering) return;
    if (_saveStatus == SaveStatus.conflict) return;
    final question = q.question(questionId);
    if (question == null) return;
    final clean = sanitizeAnswers(q, {questionId: Answer.of(question, value)});
    _answers = {..._answers}..remove(questionId);
    if (clean[questionId] != null) _answers[questionId] = clean[questionId]!;
    _dirty = true;
    _mutation++;
    _submitProblem = null;
    _missing = const [];
    _notify();
    unawaited(_writeLocal());
    _schedule(debounce);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(_flush()));
  }

  /// Sends the current answers if they changed. Concurrent calls share one
  /// request at a time.
  Future<void> _flush() async {
    while (_saving != null) {
      await _saving;
    }
    if (!_dirty || locked || _saveStatus == SaveStatus.conflict) return;
    final completer = Completer<void>();
    _saving = completer.future;
    try {
      await _saveOnce();
    } finally {
      _saving = null;
      completer.complete();
    }
  }

  Future<void> _saveOnce() async {
    final mutation = _mutation;
    if (_saveKeyMutation != mutation) {
      _saveKey = _newKey();
      _saveKeyMutation = mutation;
    }
    _saveStatus = SaveStatus.saving;
    _notify();
    try {
      final ack = await api.autosave(
        assignment.attemptId,
        expectedRevision: _serverRevision,
        answers: sendableAnswers(_questionnaire!, _answers),
        idempotencyKey: _saveKey!,
      );
      if (_disposed || locked) return;
      _serverRevision = ack.revision;
      _saveKey = null;
      _saveKeyMutation = null;
      _dirty = mutation != _mutation;
      _saveStatus = _dirty ? SaveStatus.saving : SaveStatus.saved;
      await _writeLocal();
      if (_dirty) _schedule(Duration.zero);
    } on PlatformException catch (e) {
      if (_disposed) return;
      switch (e.code) {
        case PlatformErrorCode.network ||
            PlatformErrorCode.timeout ||
            PlatformErrorCode.notConfigured:
          // The same save is retried later with the same key.
          _saveStatus = SaveStatus.offline;
        case PlatformErrorCode.conflict ||
            PlatformErrorCode.revisionConflict ||
            PlatformErrorCode.attemptSubmitted:
          await _afterConflict();
        default:
          _saveKey = null;
          _saveKeyMutation = null;
          _saveStatus = SaveStatus.notSaved;
      }
    } catch (_) {
      if (!_disposed) _saveStatus = SaveStatus.notSaved;
    }
    _notify();
  }

  /// A 409 `conflict` carries no revision (flat ErrorDTO): the detail says
  /// whether the attempt was submitted or saved elsewhere.
  Future<void> _afterConflict() async {
    try {
      final detail = await api.detail(assignment.assignmentId);
      switch (detail) {
        case SubmittedAssignment(:final acknowledgement):
          // Submitted elsewhere: this device's edits never reopen it.
          await _lock(acknowledgement.submittedAt);
        case OpenAssignment(:final attempt)
            when attempt.revision != _serverRevision:
          _conflictLocal = {..._answers};
          _remoteRevision = attempt.revision;
          _saveStatus = SaveStatus.conflict;
        case OpenAssignment():
          _saveKey = null;
          _saveKeyMutation = null;
          _saveStatus = SaveStatus.notSaved;
      }
    } on PlatformException catch (_) {
      _saveStatus = SaveStatus.offline;
    }
  }

  // ── Conflict resolution (unfinished attempts only) ─────────────────────

  /// "Load the saved answers": the server's confirmed state replaces this
  /// device's unsynced edits.
  Future<void> resolveUseServer() async {
    try {
      final detail = await api.detail(assignment.assignmentId);
      switch (detail) {
        case SubmittedAssignment(:final acknowledgement):
          await _lock(acknowledgement.submittedAt);
        case OpenAssignment(:final attempt):
          _conflictLocal = null;
          _remoteRevision = null;
          _dirty = false;
          if (attempt.versionId != assignment.versionId) {
            _phase = AttemptPhase.unavailable;
            _loadError = AttemptLoadError.unsupported;
          } else {
            await _adopt(attempt);
          }
      }
    } on PlatformException catch (_) {
      _saveStatus = SaveStatus.conflict;
    }
    _notify();
  }

  /// "Keep this device's answers": only for the SAME version and an
  /// unfinished attempt; the server's newest revision is replaced on
  /// purpose by the user's choice.
  Future<void> resolveKeepMine() async {
    final mine = _conflictLocal;
    if (mine == null) return;
    try {
      final detail = await api.detail(assignment.assignmentId);
      switch (detail) {
        case SubmittedAssignment(:final acknowledgement):
          await _lock(acknowledgement.submittedAt);
          _notify();
          return;
        case OpenAssignment(:final attempt)
            when attempt.versionId != assignment.versionId:
          await resolveUseServer();
          return;
        case OpenAssignment(:final attempt):
          _serverRevision = attempt.revision;
      }
      _answers = mine;
      _conflictLocal = null;
      _remoteRevision = null;
      _dirty = true;
      _mutation++;
      _saveStatus = SaveStatus.idle;
      await _writeLocal();
      await _flush();
    } on PlatformException catch (_) {
      _saveStatus = SaveStatus.conflict;
    }
    _notify();
  }

  // ── Restart ────────────────────────────────────────────────────────────

  /// Clears an UNFINISHED attempt on the server (after the user confirmed)
  /// with an autosave of no answers (the web's Restart). Returns false when
  /// refused
  /// (submitted, newer elsewhere, offline).
  Future<bool> restart() async {
    if (locked || _phase != AttemptPhase.answering) return false;
    _timer?.cancel();
    while (_saving != null) {
      await _saving;
    }
    try {
      final ack = await api.autosave(
        assignment.attemptId,
        expectedRevision: _remoteRevision ?? _serverRevision,
        answers: const [],
        idempotencyKey: _newKey(),
      );
      _serverRevision = ack.revision;
      _answers = {};
      _conflictLocal = null;
      _remoteRevision = null;
      _idempotencyKey = null;
      _saveKey = null;
      _saveKeyMutation = null;
      _dirty = false;
      _mutation++;
      _index = 0;
      _missing = const [];
      _submitProblem = null;
      _saveStatus = SaveStatus.saved;
      await _writeLocal();
      _notify();
      return true;
    } on PlatformException catch (e) {
      if (e.code == PlatformErrorCode.conflict ||
          e.code == PlatformErrorCode.revisionConflict ||
          e.code == PlatformErrorCode.attemptSubmitted) {
        await _afterConflict();
      }
      _notify();
      return false;
    }
  }

  /// "Next" on an unanswered required question.
  void markUnanswered(String questionId) {
    _missing = [questionId];
    _submitProblem = SubmitProblem.incomplete;
    _notify();
  }

  // ── Submit ─────────────────────────────────────────────────────────────

  /// Validates, makes sure the server has these exact answers, then submits
  /// ONCE with an idempotency key and the expected revision. A timeout is
  /// resolved by reading the assignment (submitted or not), and a retry
  /// always reuses the same key, so it can never submit twice.
  Future<bool> submit() async {
    final q = _questionnaire;
    if (q == null || _phase != AttemptPhase.answering) return locked;
    _missing = missingRequired(q, _answers);
    if (_missing.isNotEmpty) {
      _submitProblem = SubmitProblem.incomplete;
      _index = q.questions.indexWhere((x) => x.id == _missing.first);
      _notify();
      return false;
    }
    if (_saveStatus == SaveStatus.conflict) {
      _submitProblem = SubmitProblem.conflict;
      _notify();
      return false;
    }
    _phase = AttemptPhase.submitting;
    _submitProblem = null;
    _notify();

    _timer?.cancel();
    await _flush();
    if (locked) {
      _notify();
      return true;
    }
    if (_dirty || _saveStatus == SaveStatus.conflict) {
      _phase = AttemptPhase.answering;
      _submitProblem = switch (_saveStatus) {
        SaveStatus.conflict => SubmitProblem.conflict,
        SaveStatus.offline => SubmitProblem.offline,
        _ => SubmitProblem.other,
      };
      _notify();
      return false;
    }

    // The key is stored BEFORE the request leaves, so a retry after a
    // timeout or an app restart re-uses it.
    final key = _idempotencyKey ??= _newKey();
    await _writeLocal();
    SubmitAck? ack;
    try {
      ack = await api.submit(
        assignment.attemptId,
        expectedRevision: _serverRevision,
        idempotencyKey: key,
      );
    } on PlatformException catch (e) {
      final problem = switch (e.code) {
        PlatformErrorCode.reauthRequired => SubmitProblem.reauth,
        PlatformErrorCode.network => SubmitProblem.offline,
        PlatformErrorCode.timeout => SubmitProblem.unconfirmed,
        PlatformErrorCode.conflict ||
        PlatformErrorCode.revisionConflict ||
        PlatformErrorCode.attemptSubmitted => SubmitProblem.conflict,
        _ => SubmitProblem.other,
      };
      if (problem == SubmitProblem.offline ||
          problem == SubmitProblem.unconfirmed ||
          problem == SubmitProblem.conflict) {
        // Did it land (here or from another device)?
        ack = await _submittedAckOrNull();
      }
      if (ack == null) {
        if (problem == SubmitProblem.conflict) await _afterConflict();
        if (!locked) {
          _phase = AttemptPhase.answering;
          _submitProblem = problem;
        }
        _notify();
        return locked;
      }
    } on FormatException {
      // A reply that is not exactly the four-field acknowledgement is never
      // read. Whether it landed is decided by the assignment detail; a
      // retry re-uses the same key.
      ack = await _submittedAckOrNull();
      if (ack == null) {
        _phase = AttemptPhase.answering;
        _submitProblem = SubmitProblem.unconfirmed;
        _notify();
        return false;
      }
    }
    await _lock(ack.submittedAt);
    _notify();
    return true;
  }

  Future<SubmitAck?> _submittedAckOrNull() async {
    try {
      final detail = await api.detail(assignment.assignmentId);
      return detail is SubmittedAssignment ? detail.acknowledgement : null;
    } catch (_) {
      return null;
    }
  }

  /// Relationship removed / account switched: stop everything and forget.
  Future<void> discard() async {
    _timer?.cancel();
    await drafts.delete(uid, assignment.attemptId);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _onlineSub?.cancel();
    super.dispose();
  }
}
