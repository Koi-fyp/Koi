import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

enum Emotion { neutral, joy, angry, sorrow, fun }

extension EmotionWire on Emotion {
  String get wireName => name;

  static Emotion parse(Object? value) {
    return Emotion.values.firstWhere(
      (emotion) => emotion.name == value,
      orElse: () => Emotion.neutral,
    );
  }
}

class CompanionState {
  const CompanionState(this.emotion, this.intensity);
  final Emotion emotion;
  final double intensity;

  factory CompanionState.fromJson(Object? value) {
    final map = value is Map ? value : const <Object?, Object?>{};
    final raw = map['emotion'];
    final intensity = map['intensity'];
    final number = intensity is num ? intensity.toDouble().clamp(0.0, 1.0) : 0.4;
    return CompanionState(EmotionWire.parse(raw), number);
  }

  Map<String, Object> toJson() => {
        'emotion': emotion.wireName,
        'intensity': intensity,
      };
}

enum ChatRole { user, assistant }

class ChatTurn {
  const ChatTurn(this.role, this.content);
  final ChatRole role;
  final String content;

  Map<String, String> toJson() => {'role': role.name, 'content': content};
}

enum ClientEvent {
  none,
  playbackDone,
  playbackStopped,
  startBreathing,
  startGrounding,
  startPlan,
}

extension ClientEventWire on ClientEvent {
  String get wireName => switch (this) {
        ClientEvent.playbackDone => 'playback_done',
        ClientEvent.playbackStopped => 'playback_stopped',
        ClientEvent.startBreathing => 'start_breathing',
        ClientEvent.startGrounding => 'start_grounding',
        ClientEvent.startPlan => 'start_plan',
        ClientEvent.none => 'none',
      };
}

class UiAction {
  const UiAction(this.name, this.args);
  final String name;
  final Map<String, Object?> args;
}

class Handoff {
  const Handoff(this.to, this.reason);
  final String to;
  final String reason;
}

class CrisisResult {
  const CrisisResult({
    required this.crisisScore,
    required this.riskCategory,
    required this.modalitiesUsed,
    required this.triggerFlags,
    this.confidence,
    this.confidenceReasons = const [],
    this.turnId,
  });
  final double crisisScore;
  final String riskCategory;
  final List<String> modalitiesUsed;
  final List<String> triggerFlags;
  final String? confidence;
  final List<String> confidenceReasons;
  final String? turnId;

  factory CrisisResult.fromJson(Map<String, Object?> json) => CrisisResult(
        crisisScore: (json['crisis_score'] as num?)?.toDouble() ?? 0,
        riskCategory: json['risk_category'] as String? ?? 'LOW',
        modalitiesUsed: [for (final value in (json['modalities_used'] as List?) ?? const []) '$value'],
        triggerFlags: [for (final value in (json['trigger_flags'] as List?) ?? const []) '$value'],
        confidence: json['confidence'] as String?,
        confidenceReasons: [
          for (final value in (json['confidence_reasons'] as List?) ?? const []) '$value'
        ],
        turnId: json['turn_id'] as String?,
      );

  bool get isHighOrCritical => riskCategory == 'HIGH' || riskCategory == 'CRITICAL';
}

class ChatResult {
  const ChatResult({
    required this.reply,
    required this.companionState,
    required this.uiActions,
    required this.handoff,
    required this.latencyMs,
  });
  final String reply;
  final CompanionState companionState;
  final List<UiAction> uiActions;
  final Handoff? handoff;
  final int? latencyMs;
}

class ChatHandlers {
  const ChatHandlers({
    this.onCompanionState,
    this.onDelta,
    this.onUiAction,
    this.onHandoff,
    this.onCrisis,
  });
  final void Function(CompanionState state)? onCompanionState;
  final void Function(String text)? onDelta;
  final void Function(UiAction action, bool urgent)? onUiAction;
  final void Function(Handoff handoff)? onHandoff;
  final void Function(CrisisResult result)? onCrisis;
}

class CrisisInput {
  const CrisisInput({this.text, this.audio, this.video, this.language, required this.turnId});
  final String? text;
  final http.MultipartFile? audio;
  final http.MultipartFile? video;
  final String? language;
  final String turnId;
}

class KoiConversationState {
  String? exerciseState;
  ClientEvent pendingClientEvent = ClientEvent.none;
  CrisisResult? latestRisk;
  bool latestRiskSent = false;
  bool crisisFlowOpen = false;
  String? pendingCrisisResolution;
  int turnSeq = 0;
  int _latestRiskSeq = -1;
  int _minRiskSeq = 0;

  void markPlayback(bool done) {
    pendingClientEvent = done ? ClientEvent.playbackDone : ClientEvent.playbackStopped;
  }

  void startExercise(ClientEvent kind) {
    if (kind == ClientEvent.startBreathing ||
        kind == ClientEvent.startGrounding ||
        kind == ClientEvent.startPlan) {
      pendingClientEvent = kind;
    }
  }

  void resolveCrisis(String path) {
    pendingCrisisResolution = path;
    crisisFlowOpen = false;
    latestRisk = null;
    latestRiskSent = true;
    _minRiskSeq = turnSeq + 1;
  }

  bool acceptRisk(CrisisResult result, int sequence) {
    if (sequence < _minRiskSeq || sequence <= _latestRiskSeq) return false;
    latestRisk = result;
    _latestRiskSeq = sequence;
    latestRiskSent = false;
    return true;
  }
}

class KoiChatClient {
  KoiChatClient({
    required String chatBaseUrl,
    required String crisisBaseUrl,
    required this.getToken,
    http.Client? client,
  })  : chatBaseUrl = chatBaseUrl.replaceFirst(RegExp(r'/$'), ''),
        crisisBaseUrl = crisisBaseUrl.replaceFirst(RegExp(r'/$'), ''),
        _client = client ?? http.Client();

  final String chatBaseUrl;
  final String crisisBaseUrl;
  final Future<String> Function() getToken;
  final http.Client _client;

  Future<CrisisResult?> checkCrisis(CrisisInput input) async {
    if (crisisBaseUrl.isEmpty) return null;
    return _checkCrisis(input).timeout(
      const Duration(seconds: 20),
      onTimeout: () => null,
    );
  }

  Future<CrisisResult?> _checkCrisis(CrisisInput input) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$crisisBaseUrl/api/v1/crisis'),
      )..headers['Authorization'] = 'Bearer ${await getToken()}';
      if (input.text != null && input.audio == null) request.fields['text'] = input.text!;
      if (input.audio != null) request.files.add(input.audio!);
      if (input.video != null) request.files.add(input.video!);
      if (input.language != null) request.fields['language'] = input.language!;
      request.fields['turn_id'] = input.turnId;
      final response = await _client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final json = jsonDecode(await response.stream.bytesToString());
      return json is Map ? CrisisResult.fromJson(Map<String, Object?>.from(json)) : null;
    } catch (_) {
      return null;
    }
  }

  Future<ChatResult> sendMessage({
    required String text,
    required List<ChatTurn> history,
    required KoiConversationState state,
    ChatHandlers handlers = const ChatHandlers(),
    CrisisInput? crisisInput,
  }) async {
    final sequence = ++state.turnSeq;
    if (crisisInput != null) {
      unawaited(checkCrisis(crisisInput).then((result) {
        if (result == null || !state.acceptRisk(result, sequence)) return;
        if (result.isHighOrCritical && !state.crisisFlowOpen) {
          state.crisisFlowOpen = true;
          handlers.onCrisis?.call(result);
        }
      }));
    }

    try {
      final body = <String, Object?>{
        'message': text,
        'session_history': [for (final turn in history) turn.toJson()],
        'exercise_state': state.exerciseState,
        'client_event': state.pendingClientEvent.wireName,
      };
      final risk = state.latestRisk;
      if (risk != null) {
        body['risk'] = {
          'risk_category': risk.riskCategory,
          'crisis_score': risk.crisisScore,
          'trigger_flags': risk.triggerFlags,
          'is_new': !state.latestRiskSent,
        };
      }
      if (state.pendingCrisisResolution != null) {
        body['policy_event'] = 'crisis_resolved';
        body['crisis_path'] = state.pendingCrisisResolution;
      }
      final effectiveHandlers = ChatHandlers(
        onCompanionState: handlers.onCompanionState,
        onDelta: handlers.onDelta,
        onUiAction: handlers.onUiAction,
        onCrisis: handlers.onCrisis,
        onHandoff: (handoff) {
          if (!state.crisisFlowOpen) {
            state.crisisFlowOpen = true;
            handlers.onHandoff?.call(handoff);
          }
        },
      );
      final result = await _streamChat(body, effectiveHandlers);
      state.pendingClientEvent = ClientEvent.none;
      state.pendingCrisisResolution = null;
      if (state.latestRisk != null) state.latestRiskSent = true;
      state.exerciseState = result.exerciseState ?? state.exerciseState;
      return result.chatResult;
    } catch (_) {
      return const ChatResult(
        reply: "I'm having a little trouble connecting right now. I'm still here with you.",
        companionState: CompanionState(Emotion.neutral, 0.4),
        uiActions: [],
        handoff: null,
        latencyMs: null,
      );
    }
  }

  Future<_StreamResult> _streamChat(
      Map<String, Object?> body, ChatHandlers handlers) async {
    final request = http.Request('POST', Uri.parse('$chatBaseUrl/api/v1/chat'))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await getToken()}',
      })
      ..body = jsonEncode(body);
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('chat returned ${response.statusCode}');
    }
    final out = _MutableChatResult();
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      out.buffer += chunk;
      final frames = out.buffer.split('\n\n');
      out.buffer = frames.removeLast();
      for (final frame in frames) {
        _handleFrame(frame, out, handlers);
      }
    }
    if (out.buffer.trim().isNotEmpty) _handleFrame(out.buffer, out, handlers);
    return _StreamResult(out.freeze(), out.exerciseState);
  }

  void _handleFrame(String frame, _MutableChatResult out, ChatHandlers handlers) {
    var event = 'message';
    final data = <String>[];
    for (final line in frame.split('\n')) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data.add(line.substring(5).trimLeft());
      }
    }
    if (data.isEmpty) return;
    try {
      final decoded = jsonDecode(data.join('\n'));
      if (decoded is! Map) return;
      final map = Map<String, Object?>.from(decoded);
      switch (event) {
        case 'latency':
          out.latencyMs = (map['latency_ms'] as num?)?.toInt();
        case 'companion_state':
          out.companionState = CompanionState.fromJson(map);
          handlers.onCompanionState?.call(out.companionState);
        case 'delta':
          final text = map['text'];
          if (text is String && text.isNotEmpty) {
            out.reply += text;
            out.sawText = true;
            handlers.onDelta?.call(text);
          }
        case 'ui_action':
          final args = map['args'];
          final action = UiAction(
            '${map['name'] ?? ''}',
            args is Map ? Map<String, Object?>.from(args) : <String, Object?>{},
          );
          out.uiActions.add(action);
          handlers.onUiAction?.call(action, !out.sawText);
        case 'handoff':
          if (map['to'] == 'crisis') {
            out.handoff = Handoff('crisis', '${map['reason'] ?? ''}');
            handlers.onHandoff?.call(out.handoff!);
          }
        case 'state':
          if (map['exercise_state'] is String) out.exerciseState = map['exercise_state'] as String;
        case 'done':
          if (map['full_text'] is String && (map['full_text'] as String).isNotEmpty) {
            out.reply = map['full_text'] as String;
          }
          if (map['companion_state'] != null) {
            out.companionState = CompanionState.fromJson(map['companion_state']);
          }
          if (map['exercise_state'] is String) out.exerciseState = map['exercise_state'] as String;
      }
    } catch (_) {
      // Malformed and unknown SSE frames are intentionally ignored.
    }
  }
}

class _MutableChatResult {
  String buffer = '';
  String reply = '';
  CompanionState companionState = const CompanionState(Emotion.neutral, 0.4);
  final List<UiAction> uiActions = [];
  Handoff? handoff;
  int? latencyMs;
  String? exerciseState;
  bool sawText = false;

  ChatResult freeze() => ChatResult(
        reply: reply,
        companionState: companionState,
        uiActions: List.unmodifiable(uiActions),
        handoff: handoff,
        latencyMs: latencyMs,
      );
}

class _StreamResult {
  const _StreamResult(this.chatResult, this.exerciseState);
  final ChatResult chatResult;
  final String? exerciseState;
}
