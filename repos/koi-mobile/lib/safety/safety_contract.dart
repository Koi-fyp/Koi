/// Dart shapes for the crisis and breathing parts of the KOI client contract.
///
/// Source: repos/koi-ai-engine/docs/contracts/KOI_CLIENT_CONTRACT_v1.md on
/// origin/feat/exercise-director-modal (PROPOSED, Oct 16 2026): §1 request
/// fields, §2 `ui_action` / `handoff` events and `start_breathing` args, §4
/// crisis result + `intervention_content`, v1.1 `risk` event.
///
/// Only the fields the contract names are modelled. Unknown fields are
/// ignored (§2 "Unknown events must be ignored", §4 rule 6). Nothing here
/// talks to the backend or parses SSE; the wiring owner feeds these in.
library;

/// `risk_category`: exactly `LOW | MODERATE | HIGH | CRITICAL`.
enum RiskCategory {
  low('LOW'),
  moderate('MODERATE'),
  high('HIGH'),
  critical('CRITICAL');

  const RiskCategory(this.wire);
  final String wire;

  /// null for anything that is not one of the four names.
  static RiskCategory? parse(Object? value) {
    for (final c in values) {
      if (c.wire == value) return c;
    }
    return null;
  }

  /// §4 rule 2: HIGH or CRITICAL shows the crisis flow.
  bool get showsCrisisFlow => this == high || this == critical;
}

/// `intervention_content.source`: `grounded | fallback`.
enum InterventionSource {
  grounded('grounded'),
  fallback('fallback');

  const InterventionSource(this.wire);
  final String wire;

  static InterventionSource? parse(Object? value) {
    for (final s in values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

/// One `intervention_content.items[]` entry:
/// `{text, chunk_id, source_corpus, evidence_role, review_status}`.
class InterventionItem {
  const InterventionItem({
    required this.text,
    this.chunkId,
    this.sourceCorpus,
    this.evidenceRole,
    this.reviewStatus,
  });

  final String text;
  final String? chunkId;
  final String? sourceCorpus;

  // TODO(contract): the contract names evidence_role and review_status but
  // defines no values for them (the built-in fallback uses "safety-message" /
  // "not-required"). UX Flows v1.3/v1.4 says clinician-only content must never
  // be shown, but nothing in the contract marks an item as clinician-only, so
  // no item is filtered on these yet.
  final String? evidenceRole;
  final String? reviewStatus;

  /// null when `text` is missing or blank.
  static InterventionItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    if (text is! String || text.trim().isEmpty) return null;
    return InterventionItem(
      text: text,
      chunkId: _string(raw['chunk_id']),
      sourceCorpus: _string(raw['source_corpus']),
      evidenceRole: _string(raw['evidence_role']),
      reviewStatus: _string(raw['review_status']),
    );
  }
}

/// `intervention_content.helpline`: `{name, number, verified}`.
class Helpline {
  const Helpline({
    required this.name,
    required this.number,
    this.verified = false,
  });

  final String name;
  final String number;

  /// Contract §5: nobody has phoned it, `verified` stays false. The UI never
  /// shows "verified" wording either way.
  final bool verified;

  /// Used when the payload has no usable helpline. Same default as the
  /// backend (deploy/modal/crisis_app.py KOI_HELPLINE_NAME/NUMBER).
  // TODO(helpline): 1166 is not verified (contract §5: nobody has phoned it;
  // sources don't describe it as a crisis line or 24-hour service).
  static const Helpline defaultHelpline = Helpline(
    name: 'Sehat Tahaffuz 1166 (Humraaz mental health service)',
    number: '1166',
  );

  /// null when `name` or `number` is missing or blank.
  static Helpline? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final number = raw['number'];
    if (name is! String || name.trim().isEmpty) return null;
    if (number is! String || number.trim().isEmpty) return null;
    return Helpline(
      name: name,
      number: number,
      verified: raw['verified'] == true,
    );
  }
}

/// `intervention_content` (present only at HIGH/CRITICAL):
/// `{source: grounded|fallback, language, items[1-3], helpline}`.
class InterventionContent {
  const InterventionContent({
    required this.source,
    required this.items,
    this.language,
    this.helpline,
  });

  final InterventionSource source;
  final String? language;

  /// 1 to 3 items (contract). [fromJson] keeps at most [maxItems].
  final List<InterventionItem> items;
  final Helpline? helpline;

  static const int maxItems = 3;

  /// null unless `source` is grounded|fallback and there is at least one
  /// item with text, like the backend's own check (koi_crisis_core.py
  /// `_valid_content`). Extra items past the third are dropped.
  static InterventionContent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final source = InterventionSource.parse(raw['source']);
    final rawItems = raw['items'];
    if (source == null || rawItems is! List) return null;
    final items = <InterventionItem>[];
    for (final r in rawItems) {
      final item = InterventionItem.fromJson(r);
      if (item == null) return null;
      if (items.length < maxItems) items.add(item);
    }
    if (items.isEmpty) return null;
    return InterventionContent(
      source: source,
      language: _string(raw['language']),
      items: List.unmodifiable(items),
      helpline: Helpline.fromJson(raw['helpline']),
    );
  }
}

/// `risk.model`: `{version, calibrated}`.
class RiskModelInfo {
  const RiskModelInfo({this.version, this.calibrated});
  final String? version;
  final bool? calibrated;

  static RiskModelInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final calibrated = raw['calibrated'];
    return RiskModelInfo(
      version: _string(raw['version']),
      calibrated: calibrated is bool ? calibrated : null,
    );
  }
}

/// The v1.1 `risk` event (also `done.risk`), which carries the same fields
/// as the §4 crisis result plus `status`.
///
/// `crisis_score` is kept because the contract sends it, but it is NEVER
/// shown to the user (Flow 4 shows the category and the content only).
class RiskResult {
  const RiskResult({
    this.status,
    this.riskCategory,
    this.crisisScore,
    this.confidence,
    this.confidenceReasons = const [],
    this.modalitiesUsed = const [],
    this.triggerFlags = const [],
    this.interventionContent,
    this.model,
  });

  /// `ok | unavailable` (v1.1). null on a §4 result, which has no status.
  final String? status;
  final RiskCategory? riskCategory;
  final double? crisisScore;

  /// `standard | reduced`.
  final String? confidence;
  final List<String> confidenceReasons;

  /// `text | audio | video`.
  final List<String> modalitiesUsed;
  final List<String> triggerFlags;
  final InterventionContent? interventionContent;
  final RiskModelInfo? model;

  static const String statusUnavailable = 'unavailable';

  /// v1.1: "Unavailable never means safe": there is no score this turn.
  bool get isUnavailable => status == statusUnavailable;

  /// §4 rule 3: `confidence: "reduced"` → show "limited information".
  bool get isReducedConfidence => confidence == 'reduced';

  bool get showsCrisisFlow =>
      !isUnavailable && (riskCategory?.showsCrisisFlow ?? false);

  static RiskResult fromJson(Map<String, Object?> json) {
    final score = json['crisis_score'];
    return RiskResult(
      status: _string(json['status']),
      riskCategory: RiskCategory.parse(json['risk_category']),
      crisisScore: score is num ? score.toDouble() : null,
      confidence: _string(json['confidence']),
      confidenceReasons: _strings(json['confidence_reasons']),
      modalitiesUsed: _strings(json['modalities_used']),
      triggerFlags: _strings(json['trigger_flags']),
      interventionContent: InterventionContent.fromJson(
        json['intervention_content'],
      ),
      model: RiskModelInfo.fromJson(json['model']),
    );
  }
}

/// The `handoff` event: `{"to": "crisis", "reason": "string"}`.
class Handoff {
  const Handoff({required this.to, required this.reason});
  final String to;
  final String reason;

  bool get isCrisis => to == 'crisis';

  static Handoff? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final to = raw['to'];
    if (to is! String) return null;
    return Handoff(to: to, reason: _string(raw['reason']) ?? '');
  }
}

/// The `ui_action` event: `{"name": "...", "args": {...}}`.
class UiAction {
  const UiAction(this.name, [this.args = const {}]);
  final String name;
  final Map<String, Object?> args;

  static const String startBreathing = 'start_breathing';
  static const String stopBreathing = 'stop_breathing';
  static const String pauseBreathing = 'pause_breathing';

  // TODO(exercises): start_grounding, start_plan, save_task, save_go_to are
  // also ui_actions; nothing on mobile handles them yet.

  static UiAction? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String) return null;
    final args = raw['args'];
    return UiAction(
      name,
      args is Map ? Map<String, Object?>.from(args) : const {},
    );
  }
}

/// `start_breathing` args: `{pattern, inhale_s, exhale_s, cycles, cue_audio,
/// minutes_note}`. Timings are bounded for the phone UI exactly like Web
/// (feat/avatar-webview-host lib/conversation/exerciseContract.ts
/// parseBreathingPattern): 1–12 s per phase, 1–12 whole cycles, cues trimmed
/// to 120 characters.
class BreathingPattern {
  const BreathingPattern({
    required this.inhaleS,
    required this.exhaleS,
    required this.cycles,
    required this.cueIn,
    required this.cueOut,
    this.pattern,
    this.minutesNote,
  });

  final double inhaleS;
  final double exhaleS;
  final int cycles;

  /// `cue_audio[0]` / `cue_audio[1]`, already in the conversation language.
  /// Shown on screen only.
  // TODO(audio): cue_audio is text for TTS; no audio is played yet.
  final String cueIn;
  final String cueOut;

  final String? pattern;
  final String? minutesNote;

  static const double maxPhaseSeconds = 12;
  static const int maxCycles = 12;
  static const int maxCueLength = 120;

  double get cycleSeconds => inhaleS + exhaleS;
  double get totalSeconds => cycleSeconds * cycles;

  /// null when a timing or either cue is missing or invalid (Web then shows
  /// "Breathing guidance is unavailable …").
  static BreathingPattern? fromArgs(Map<String, Object?> args) {
    final inhale = _positive(args['inhale_s']);
    final exhale = _positive(args['exhale_s']);
    final cycles = _positive(args['cycles']);
    final cues = args['cue_audio'];
    if (inhale == null || exhale == null || cycles == null) return null;
    if (cues is! List || cues.length < 2) return null;
    final rawIn = cues[0];
    final rawOut = cues[1];
    if (rawIn is! String || rawOut is! String) return null;
    final cueIn = _cue(rawIn);
    final cueOut = _cue(rawOut);
    if (cueIn.isEmpty || cueOut.isEmpty) return null;
    return BreathingPattern(
      inhaleS: inhale.clamp(1, maxPhaseSeconds).toDouble(),
      exhaleS: exhale.clamp(1, maxPhaseSeconds).toDouble(),
      cycles: cycles.floor().clamp(1, maxCycles),
      cueIn: cueIn,
      cueOut: cueOut,
      pattern: _string(args['pattern']),
      minutesNote: _string(args['minutes_note']),
    );
  }

  static double? _positive(Object? v) =>
      v is num && v.isFinite && v > 0 ? v.toDouble() : null;

  // JS `.trim().slice(0, 120)`.
  static String _cue(String s) {
    final t = s.trim();
    return t.length <= maxCueLength ? t : t.substring(0, maxCueLength);
  }
}

/// `client_event` (§1): `none | playback_done | playback_stopped |
/// start_breathing | start_grounding | start_plan`.
enum ClientEvent {
  none('none'),
  playbackDone('playback_done'),
  playbackStopped('playback_stopped'),
  startBreathing('start_breathing'),
  startGrounding('start_grounding'),
  startPlan('start_plan');

  const ClientEvent(this.wire);
  final String wire;
}

/// `crisis_path`, sent with `policy_event: "crisis_resolved"` (§1).
enum CrisisPath {
  reachedOut('reached_out'),
  saidButDidNot('said_but_did_not'),
  misunderstanding('misunderstanding');

  const CrisisPath(this.wire);
  final String wire;
}

/// `policy_event` value sent with [CrisisPath].
const String crisisResolvedPolicyEvent = 'crisis_resolved';

String? _string(Object? v) => v is String ? v : null;

List<String> _strings(Object? v) =>
    v is List ? List.unmodifiable(v.whereType<String>()) : const [];
