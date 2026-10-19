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
  /// unsupported version). [AttemptController.loadError] says which.
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

  /// Saved on this device only. Never shown as being on another device.
  offline,

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
  other,
}

/// One patient's attempt: load → answer (debounced autosave with
/// revisions) → submit (idempotent) → submitted (terminal).
///
/// Rules (KOI_MOBILE_TRACK_FINAL_REVIEWED.md §6):
/// - only whitelisted answer fields are sent, with the revision last seen;
/// - a newer remote revision is NEVER overwritten silently: the state goes
///   to [SaveStatus.conflict] and the user chooses (reload the saved
///   answers, or keep this device's answers for this same version);
/// - answers are never merged across versions;
/// - once submitted (here, elsewhere, or reported by the server), the
///   attempt is locked and pending local edits are discarded: a stale
///   offline edit can never reopen it.
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
  QuestionnaireVersion? _version;
  Map<String, Answer> _answers = {};
  int _serverRevision = 0;
  bool _dirty = false;

  /// Bumped on every local change; a save that finishes for an older
  /// mutation leaves the draft dirty.
  int _mutation = 0;
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
  QuestionnaireVersion? get version => _version;
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
      final version = await api.version(assignment.versionId);
      final attempt = await api.attempt(assignment.attemptId);
      if (attempt.versionId != version.versionId) {
        // Never merge or show answers across versions.
        throw const UnsupportedQuestionnaireException('version mismatch');
      }
      _version = version;
      await _adopt(
        attempt,
        local: await drafts.load(uid, assignment.attemptId),
      );
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
    final version = _version!;
    _serverRevision = attempt.revision;
    if (attempt.status == AttemptStatus.submitted) {
      await _lock(attempt.submittedAt);
      return;
    }
    final server = sanitizeAnswers(version, attempt.answers);
    _idempotencyKey = local?.idempotencyKey;
    if (local != null && local.versionId == version.versionId && local.dirty) {
      final mine = sanitizeAnswers(version, local.answers);
      if (local.baseRevision == attempt.revision) {
        // Nothing newer remotely: this device's edits continue.
        _answers = mine;
        _dirty = true;
        _phase = AttemptPhase.answering;
        _schedule(Duration.zero);
        return;
      }
      if (!mapEquals(mine, server)) {
        // A newer remote revision: never overwrite it blindly.
        _answers = server;
        _conflictLocal = mine;
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

  Future<void> _writeLocal() async {
    final v = _version;
    if (v == null || locked) return;
    try {
      await drafts.save(
        uid,
        LocalDraft(
          attemptId: assignment.attemptId,
          versionId: v.versionId,
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
    final v = _version;
    if (v == null) return;
    _index = i.clamp(0, v.questions.length - 1);
    _notify();
  }

  /// Records an answer. Ignored once locked or while in conflict (the user
  /// must resolve first, so nothing is lost or merged).
  void setAnswer(String questionId, Answer answer) {
    final v = _version;
    if (v == null || _phase != AttemptPhase.answering) return;
    if (_saveStatus == SaveStatus.conflict) return;
    final q = v.question(questionId);
    if (q == null || !q.hasWording) return;
    final clean = sanitizeAnswers(v, {questionId: answer});
    _answers = {..._answers}..remove(questionId);
    if (clean.containsKey(questionId) && !clean[questionId]!.isEmpty) {
      _answers[questionId] = clean[questionId]!;
    }
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
    _saveStatus = SaveStatus.saving;
    _notify();
    try {
      final ack = await api.saveDraft(
        assignment.attemptId,
        expectedRevision: _serverRevision,
        answers: _answers,
        clientMutationId: _newKey(),
      );
      if (_disposed || locked) return;
      _serverRevision = ack.revision;
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
          _saveStatus = SaveStatus.offline;
        case PlatformErrorCode.revisionConflict || PlatformErrorCode.conflict:
          _conflictLocal = {..._answers};
          _remoteRevision = e.currentRevision;
          _saveStatus = SaveStatus.conflict;
        case PlatformErrorCode.attemptSubmitted:
          // Submitted elsewhere: this device's edits never reopen it.
          await _lock(null);
        default:
          _saveStatus = SaveStatus.offline;
      }
    } catch (_) {
      if (!_disposed) _saveStatus = SaveStatus.offline;
    }
    _notify();
  }

  // ── Conflict resolution (unfinished attempts only) ─────────────────────

  /// "Load the saved answers": the server's confirmed state replaces this
  /// device's unsynced edits.
  Future<void> resolveUseServer() async {
    try {
      final attempt = await api.attempt(assignment.attemptId);
      _conflictLocal = null;
      _remoteRevision = null;
      _dirty = false;
      if (attempt.versionId != _version!.versionId) {
        _phase = AttemptPhase.unavailable;
        _loadError = AttemptLoadError.unsupported;
      } else {
        await _adopt(attempt);
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
      final attempt = await api.attempt(assignment.attemptId);
      if (attempt.status == AttemptStatus.submitted) {
        await _lock(attempt.submittedAt);
        _notify();
        return;
      }
      if (attempt.versionId != _version!.versionId) {
        await resolveUseServer();
        return;
      }
      _serverRevision = attempt.revision;
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

  /// Clears an UNFINISHED attempt on the server (after the user confirmed),
  /// drops pending local writes, then shows the server's fresh state.
  /// Returns false when refused (submitted, conflict, offline).
  Future<bool> restart() async {
    if (locked || _phase != AttemptPhase.answering) return false;
    _timer?.cancel();
    while (_saving != null) {
      await _saving;
    }
    try {
      final fresh = await api.restart(
        assignment.attemptId,
        expectedRevision: _remoteRevision ?? _serverRevision,
      );
      await drafts.delete(uid, assignment.attemptId);
      _conflictLocal = null;
      _remoteRevision = null;
      _idempotencyKey = null;
      _dirty = false;
      _index = 0;
      _missing = const [];
      _submitProblem = null;
      await _adopt(fresh);
      _notify();
      return true;
    } on PlatformException catch (e) {
      if (e.code == PlatformErrorCode.attemptSubmitted) {
        await _lock(null);
      } else if (e.code == PlatformErrorCode.revisionConflict) {
        _remoteRevision = e.currentRevision;
        _conflictLocal = {..._answers};
        _saveStatus = SaveStatus.conflict;
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
  /// ONCE via the authenticated submit endpoint with an idempotency key and
  /// the expected revision. A timeout is resolved by asking for the
  /// submission's status by that key, never by a blind second submit.
  Future<bool> submit() async {
    final v = _version;
    if (v == null || _phase != AttemptPhase.answering) return locked;
    _missing = missingRequired(v, _answers);
    if (_missing.isNotEmpty) {
      _submitProblem = SubmitProblem.incomplete;
      _index = v.questions.indexWhere((q) => q.id == _missing.first);
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
      _submitProblem = _saveStatus == SaveStatus.conflict
          ? SubmitProblem.conflict
          : SubmitProblem.offline;
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
        idempotencyKey: key,
        expectedRevision: _serverRevision,
      );
    } on PlatformException catch (e) {
      switch (e.code) {
        case PlatformErrorCode.attemptSubmitted:
          // "Already submitted" is a successful prior acknowledgement.
          ack =
              await _statusOrNull(key) ??
              SubmitAck(attemptId: assignment.attemptId);
        case PlatformErrorCode.timeout || PlatformErrorCode.network:
          ack = await _statusOrNull(key);
          if (ack == null) {
            _phase = AttemptPhase.answering;
            _submitProblem = e.code == PlatformErrorCode.network
                ? SubmitProblem.offline
                : SubmitProblem.unconfirmed;
            _notify();
            return false;
          }
        case PlatformErrorCode.revisionConflict:
          _remoteRevision = e.currentRevision;
          _conflictLocal = {..._answers};
          _saveStatus = SaveStatus.conflict;
          _phase = AttemptPhase.answering;
          _submitProblem = SubmitProblem.conflict;
          _notify();
          return false;
        default:
          _phase = AttemptPhase.answering;
          _submitProblem = SubmitProblem.other;
          _notify();
          return false;
      }
    }
    await _lock(ack.submittedAt);
    _notify();
    return true;
  }

  Future<SubmitAck?> _statusOrNull(String key) async {
    try {
      return await api.submissionStatus(
        assignment.attemptId,
        idempotencyKey: key,
      );
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
