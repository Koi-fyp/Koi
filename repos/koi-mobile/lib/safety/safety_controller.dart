import 'package:flutter/foundation.dart';

import 'safety_contract.dart';

/// What the crisis screen (UX Flow 4) shows. Never holds the crisis score.
class CrisisView {
  const CrisisView({
    this.category,
    this.content,
    this.limitedInformation = false,
  });

  /// null when the screen was opened by a `handoff` before any risk result.
  final RiskCategory? category;

  /// null → "Support details are unavailable in this chat response." (Web).
  final InterventionContent? content;

  /// §4 rule 3: `confidence == "reduced"`.
  final bool limitedInformation;

  /// The payload's helpline, else the backend default (1166).
  Helpline get helpline => content?.helpline ?? Helpline.defaultHelpline;

  /// UX Flows v1.3/v1.4: a CRITICAL response is always the fallback. Content
  /// that breaks that rule is not shown (the helpline still is), the same
  /// rule the backend applies (koi_crisis_core.py `intervention`).
  static InterventionContent? _allowed(RiskResult risk) {
    final content = risk.interventionContent;
    if (content == null) return null;
    if (risk.riskCategory == RiskCategory.critical &&
        content.source != InterventionSource.fallback) {
      return null;
    }
    return content;
  }

  static CrisisView fromRisk(RiskResult risk) => CrisisView(
    category: risk.riskCategory,
    content: _allowed(risk),
    limitedInformation: risk.isReducedConfidence,
  );
}

/// One breathing run from a `start_breathing` action.
class BreathingRun {
  const BreathingRun({
    required this.id,
    required this.pattern,
    this.paused = false,
    this.complete = false,
  });

  /// Increases with every new run; the screen restarts its clock on change.
  final int id;
  final BreathingPattern pattern;
  final bool paused;
  final bool complete;

  BreathingRun copyWith({bool? paused, bool? complete}) => BreathingRun(
    id: id,
    pattern: pattern,
    paused: paused ?? this.paused,
    complete: complete ?? this.complete,
  );
}

/// Holds the crisis-flow and breathing state driven by backend events.
///
/// The wiring owner calls [handleHandoff], [handleRisk] and [handleUiAction]
/// with parsed events and sets [onClientEvent] / [onCrisisPath] to send the
/// results on the next chat request. Until then only the debug menu feeds it
/// (simulated events).
// TODO(wiring): connect the chat SSE stream (handoff, risk, ui_action) to
// this controller, and send onClientEvent / onCrisisPath on the next request
// (crisis_path goes with policy_event "crisis_resolved", then call
// [crisisResolutionSent]).
class SafetyController extends ChangeNotifier {
  SafetyController({this.onClientEvent, this.onCrisisPath});

  /// `playback_done` / `playback_stopped`, to send on the next request.
  void Function(ClientEvent event)? onClientEvent;

  /// The Flow 4 path the user chose, to send with `policy_event:
  /// "crisis_resolved"` on the next request.
  void Function(CrisisPath path)? onCrisisPath;

  // Web notices (feat/avatar-webview-host ExerciseDirector.tsx).
  static const String noticeSafetyCheck =
      'The activity paused for a safety check.';
  static const String noticeStoppedByKoi = 'The activity was stopped by KOI.';
  static const String noticeStopped = 'Activity stopped.';
  static const String noticeInvalidPattern =
      'Breathing guidance is unavailable because its timing or cues were incomplete.';

  CrisisView? _crisis;
  BreathingRun? _breathing;
  int _runs = 0;
  int _crisisCount = 0;
  bool _resolutionPending = false;
  String? _notice;
  int _noticeSeq = 0;

  /// Non-null while the crisis screen is shown.
  CrisisView? get crisis => _crisis;

  /// Non-null while the breathing screen is shown (running, paused or
  /// complete).
  BreathingRun? get breathing => _breathing;

  /// True while a run is in progress (not complete).
  bool get breathingActive => _breathing != null && !_breathing!.complete;

  /// Increases each time the crisis screen opens; the avatar call screen
  /// listens to it to stop its animation state.
  int get crisisCount => _crisisCount;

  /// A path was chosen but the wiring hasn't confirmed it was sent yet.
  /// Repeated handoffs are ignored meanwhile (contract §1: every turn carries
  /// `handoff: crisis` until `crisis_resolved` arrives).
  bool get resolutionPending => _resolutionPending;

  /// The latest status line (Web's exerciseNotice), with a sequence number
  /// so the same text can be shown twice.
  String? get notice => _notice;
  int get noticeSeq => _noticeSeq;

  // ── Backend events ───────────────────────────────────────────────────────

  /// `handoff` (§2 event 6). Opens Flow 4 for `to == "crisis"`, unless it is
  /// already open or the user's path has not been sent yet (§3: "if Flow 4
  /// is already on screen, do not open it again").
  void handleHandoff(Handoff handoff) {
    if (!handoff.isCrisis) return;
    _openCrisis(const CrisisView());
  }

  /// The `risk` event / crisis result. HIGH or CRITICAL opens Flow 4 with
  /// its intervention content (§4 rule 2). LOW/MODERATE/unavailable change
  /// nothing here (never treated as "safe").
  void handleRisk(RiskResult risk) {
    if (!risk.showsCrisisFlow) return;
    final view = CrisisView.fromRisk(risk);
    final open = _crisis;
    if (open != null) {
      // Already on screen: never a second one. A handoff can arrive before
      // the turn's risk event, so fill in what the open screen lacks.
      if (open.content == null && open.category == null) {
        _crisis = view;
        notifyListeners();
      }
      return;
    }
    _openCrisis(view);
  }

  /// `ui_action` (§2 events 2 and 5).
  void handleUiAction(UiAction action) {
    switch (action.name) {
      case UiAction.startBreathing:
        _startBreathing(action.args);
      case UiAction.pauseBreathing:
        final run = _breathing;
        if (run == null || run.complete || run.paused) return;
        _breathing = run.copyWith(paused: true);
        notifyListeners();
      case UiAction.stopBreathing:
        _endBreathing(ClientEvent.playbackStopped, noticeStoppedByKoi);
      default:
        // Unknown or not-yet-supported actions are ignored (§2).
        return;
    }
  }

  // ── User actions ─────────────────────────────────────────────────────────

  void pauseBreathing() =>
      handleUiAction(const UiAction(UiAction.pauseBreathing));

  /// Only the user resumes (the contract has no resume action).
  void resumeBreathing() {
    final run = _breathing;
    if (run == null || run.complete || !run.paused) return;
    _breathing = run.copyWith(paused: false);
    notifyListeners();
  }

  void stopBreathing() =>
      _endBreathing(ClientEvent.playbackStopped, noticeStopped);

  /// The screen's clock reached the end of the last cycle.
  void completeBreathing() {
    final run = _breathing;
    if (run == null || run.complete) return;
    _breathing = run.copyWith(complete: true, paused: false);
    notifyListeners();
    onClientEvent?.call(ClientEvent.playbackDone);
  }

  /// Closes a finished run's screen.
  void dismissBreathing() {
    if (_breathing == null) return;
    if (breathingActive) {
      stopBreathing();
      return;
    }
    _breathing = null;
    notifyListeners();
  }

  /// One of Flow 4's three paths: closes the screen and hands the path to
  /// the wiring. The follow-up conversation continues in chat.
  void chooseCrisisPath(CrisisPath path) {
    if (_crisis == null) return;
    _crisis = null;
    _resolutionPending = true;
    notifyListeners();
    onCrisisPath?.call(path);
  }

  /// The wiring sent `policy_event: "crisis_resolved"`; a later handoff or
  /// HIGH/CRITICAL result opens Flow 4 again.
  void crisisResolutionSent() => _resolutionPending = false;

  // ── Internals ────────────────────────────────────────────────────────────

  void _openCrisis(CrisisView view) {
    if (_crisis != null || _resolutionPending) return;
    // §3 / §4 rule 2: stop any breathing animation first.
    final wasActive = breathingActive;
    _breathing = null;
    _crisis = view;
    _crisisCount++;
    if (wasActive) _setNotice(noticeSafetyCheck);
    notifyListeners();
    if (wasActive) onClientEvent?.call(ClientEvent.playbackStopped);
  }

  void _startBreathing(Map<String, Object?> args) {
    // The crisis flow comes first; no exercise while it is open.
    if (_crisis != null || _resolutionPending) return;
    final pattern = BreathingPattern.fromArgs(args);
    if (pattern == null) {
      _breathing = null;
      _setNotice(noticeInvalidPattern);
    } else {
      _breathing = BreathingRun(id: ++_runs, pattern: pattern);
    }
    notifyListeners();
  }

  void _endBreathing(ClientEvent event, String notice) {
    final wasActive = breathingActive;
    if (_breathing == null) return;
    _breathing = null;
    _setNotice(notice);
    notifyListeners();
    if (wasActive) onClientEvent?.call(event);
  }

  void _setNotice(String text) {
    _notice = text;
    _noticeSeq++;
  }
}
