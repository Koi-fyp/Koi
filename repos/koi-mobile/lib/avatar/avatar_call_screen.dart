import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../camera/camera_session.dart';
import '../camera/camera_widgets.dart';
import '../chat/backend_warmup.dart' show BackendStatus;
import '../chat/chat_controller.dart';
import '../chat/widgets/chat_widgets.dart';
import '../environment/environment_palette.dart';
import '../environment/environment_providers.dart';
import '../modes/input_mode.dart';
import '../onboarding/step_layout.dart';
import '../shell/mode_selector.dart';
import '../safety/safety_providers.dart';
import '../settings/widgets/avatar_picker.dart' show reviewCompanionSelection;
import '../theme/koi_colors.dart';
import '../voice/speech_source.dart' show VoiceKind;
import '../voice/voice_controller.dart';
import '../voice/voice_providers.dart';
import '../voice/voice_text.dart';
import '../voice_input/mic_controller.dart';
import '../voice_input/mic_providers.dart';
import '../voice_input/mic_widgets.dart';
import 'avatar_providers.dart';
import 'avatar_view.dart';
import 'call_icons.dart';

/// Video-call style conversation with the avatar. Mobile-only: there is no
/// web version of this screen yet, so the layout follows the Prompt 10 spec
/// and reuses the Chat screen's pieces (chatControllerProvider for messages
/// and sending, MessageList, InputBar, the Neo card/shadow styling, the
/// Toast).
///
/// Top to bottom: a bar with the transcript toggle, the avatar filling the
/// rest (transcript panel slides over its lower part when open; the camera
/// self-view in its corner in the camera modes), the InputBar, and the
/// call controls (Mic and Camera only in the modes that use them).
class AvatarCallScreen extends ConsumerStatefulWidget {
  const AvatarCallScreen({super.key, this.avatarController});

  /// Tests pass one to drive the avatar (fail, set emotion); otherwise the
  /// screen owns its own.
  final AvatarViewController? avatarController;

  static const String emptyTranscript = 'No messages yet.';

  /// Shown while a reply is spoken (Prompt 25).
  static const String serverVoiceLabel = 'KOI voice · lip-sync';
  static const String deviceVoiceLabel =
      'Device voice · approximate mouth movement';

  @override
  ConsumerState<AvatarCallScreen> createState() => _AvatarCallScreenState();
}

class _AvatarCallScreenState extends ConsumerState<AvatarCallScreen> {
  late final AvatarViewController _avatar =
      widget.avatarController ?? AvatarViewController();
  final FocusNode _input = FocusNode();

  // The chat stream's companion_state {emotion, intensity} (already the 5
  // AvatarEmotion names; the chat's user emotions are never mapped onto
  // it) and thinking / speaking / idle, via avatarStateSourceFactoryProvider.
  late final AvatarStateSource _stateSource;
  StreamSubscription<AvatarStateEvent>? _stateSub;

  // Voice (Prompt 25): completed replies only, never on the text Chat
  // screen. Since Prompt 29 only in the Voice and Camera view + voice modes.
  late final VoiceController _voice;
  late final AppLifecycleListener _lifecycle;
  ChatController? _chat;
  String? _uid;

  /// The latest AI message already handled (present when the screen
  /// opened, spoken, or skipped).
  String? _lastAiId;
  bool _turnOpen = false;
  int _turnCrisisCount = 0;
  int? _turnBreathingId;
  int _turnTextOnlyEvents = 0;
  int _exerciseStartsSeen = 0;

  // Mic voice input (Prompt 26): a one-shot record action; the InputBar
  // always stays. The button only shows in the modes with mic input.
  MicController? _mic;

  // Camera view (Prompt 29): a local preview only, started by a tap.
  late final CameraSession _camera;

  bool _transcriptOpen = false;

  /// Replies are spoken in the current mode (never for Koi's fox).
  bool get _spokenReplies => ref.read(effectiveInputModeProvider).spokenReplies;

  @override
  void initState() {
    super.initState();
    _setModel(ref.read(selectedAvatarProvider));
    _stateSource = ref.read(avatarStateSourceFactoryProvider)();
    _stateSub = _stateSource.events.listen(_applyState);
    _voice = ref.read(voiceControllerFactoryProvider)(
      onMouth: _avatar.setMouthCues,
    )..addListener(_voiceChanged);
    _camera = CameraSession(ref.read(localCameraFactoryProvider)())
      ..addListener(_cameraChanged);
    _lifecycle = AppLifecycleListener(onHide: _onHide, onPause: _onHide);
    final uid = _uid = ref.read(authServiceProvider).user?.uid;
    if (uid != null) {
      final chat = ref.read(chatControllerProvider(uid));
      _chat = chat;
      _lastAiId = _lastAi(chat)?.id;
      _exerciseStartsSeen = chat.exerciseStarts;
      chat.addListener(_onChat);
      _mic = MicController(
        uid: uid,
        recorder: ref.read(micRecorderFactoryProvider)(),
        prefs: ref.read(micPrefsProvider),
        send: chat.sendVoice,
        askConsent: () =>
            mounted ? showMicConsent(context) : Future.value(false),
        isBlocked: _micBlocked,
        onRecordingStarted: _stopVoiceAndMouth,
        diagnostics: ref.read(micDiagnosticsProvider),
        tempDir: ref.read(micTempDirProvider),
        now: ref.read(micClockProvider),
      )..addListener(_micChanged);
    }
    unawaited(ref.read(speechWarmupProvider).warmUp());
  }

  @override
  void dispose() {
    _chat?.removeListener(_onChat);
    _mic
      ?..removeListener(_micChanged)
      ..dispose();
    _camera
      ..removeListener(_cameraChanged)
      ..dispose();
    _lifecycle.dispose();
    _voice
      ..removeListener(_voiceChanged)
      ..dispose();
    _stateSub?.cancel();
    _stateSource.dispose();
    if (widget.avatarController == null) _avatar.dispose();
    _input.dispose();
    super.dispose();
  }

  void _setModel(AsyncValue<CompanionAvatar> selected) {
    final model = selected.valueOrNull?.model;
    if (model != null) _avatar.setAvatar(model);
  }

  /// Crisis or breathing screen open, or a crisis resolution pending.
  bool _safetyBlocks() {
    final safety = ref.read(safetyControllerProvider);
    return safety.crisis != null ||
        safety.resolutionPending ||
        safety.breathing != null;
  }

  // ── Mic (Prompt 26) ─────────────────────────────────────────────────────

  /// No recording while the crisis or breathing screen is open (or a
  /// crisis resolution is pending), nor while a reply is pending, nor in a
  /// mode without mic input.
  bool _micBlocked() =>
      _safetyBlocks() ||
      (_chat?.isTyping ?? false) ||
      !ref.read(effectiveInputModeProvider).micInput;

  /// Tap to record, tap again to send. The health warm-ups (chat, crisis,
  /// speech) start at once, so they overlap the recording.
  void _onMic() {
    final mic = _mic;
    if (mic == null) return;
    if (!mic.recording && _micBlocked()) return;
    ref.read(backendWarmupProvider).prepareAudio();
    unawaited(ref.read(speechWarmupProvider).warmUp());
    unawaited(mic.tap());
  }

  void _micChanged() {
    if (mounted) setState(() {});
  }

  /// Recording starts: phase-22 stop rules (voice and mouth stop).
  void _stopVoiceAndMouth() {
    _stopVoice();
    _avatar.setMouthCues(const []);
  }

  /// Background: voice stops, a recording is discarded, the camera closes.
  void _onHide() {
    _stopVoice();
    unawaited(_mic?.interrupt());
    _camera.stop();
  }

  /// Mode changed (Prompt 29): everything the old mode had running stops.
  void _onModeChanged() {
    _stopVoiceAndMouth();
    unawaited(_mic?.interrupt());
    _camera.stop();
  }

  // ── Camera (Prompt 29) ──────────────────────────────────────────────────

  void _cameraChanged() {
    if (mounted) setState(() {});
  }

  /// Camera button: on → off, off → on (only in a camera mode, never while
  /// the crisis or breathing screen is open).
  void _onCamera() {
    if (_camera.holdsCamera) return _camera.stop();
    if (!ref.read(effectiveInputModeProvider).cameraView || _safetyBlocks()) {
      return;
    }
    unawaited(_camera.start());
  }

  void _onText() {
    // Typing never waits for the avatar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _input.requestFocus();
    });
  }

  void _endCall() {
    _stopVoice();
    _camera.stop();
    Navigator.of(context).pop();
  }

  // ── Voice ───────────────────────────────────────────────────────────────

  void _stopVoice() => unawaited(_voice.stop());

  static ChatMessage? _lastAi(ChatController chat) {
    for (final m in chat.messages.reversed) {
      if (!m.isUser) return m;
    }
    return null;
  }

  /// While replies are spoken, the audio owns speaking / idle: text
  /// streaming shows "thinking", and nothing from the chat changes the
  /// state while a reply is audible. Emotion always passes.
  void _applyState(AvatarStateEvent event) {
    if (event is AvatarStateUpdate && _spokenReplies) {
      var state = event.conversationState;
      if (_voice.speaking != null) {
        state = null;
      } else if (state == AvatarConversationState.speaking) {
        state = AvatarConversationState.thinking;
      }
      event = AvatarStateUpdate(
        event.sessionId,
        emotion: event.emotion,
        intensity: event.intensity,
        conversationState: state,
      );
    }
    _avatar.apply(event);
  }

  void _voiceChanged() {
    if (!mounted) return;
    _avatar.setConversationState(
      _voice.speaking != null
          ? AvatarConversationState.speaking
          : AvatarConversationState.idle,
    );
    setState(() {});
  }

  /// A send starts a turn (and stops any reply still playing); its end
  /// with a new AI message is the `done` reply, the only thing spoken.
  /// An exercise start discards a recording in progress.
  void _onChat() {
    final chat = _chat;
    if (chat == null || !mounted) return;
    if (chat.exerciseStarts != _exerciseStartsSeen) {
      _exerciseStartsSeen = chat.exerciseStarts;
      unawaited(_mic?.interrupt());
    }
    if (chat.isTyping && !_turnOpen) {
      _turnOpen = true;
      _stopVoice();
      final safety = ref.read(safetyControllerProvider);
      _turnCrisisCount = safety.crisisCount;
      _turnBreathingId = safety.breathing?.id;
      _turnTextOnlyEvents = chat.textOnlyEvents;
      return;
    }
    if (chat.isTyping || !_turnOpen) return;
    _turnOpen = false;
    final last = _lastAi(chat);
    if (last == null || last.id == _lastAiId) return;
    _lastAiId = last.id;
    if (!_spokenReplies || last.isFallback || _textOnlyTurn(chat)) return;
    unawaited(_speakReply(last.content));
  }

  /// Crisis and exercise content is never spoken: a handoff, a HIGH /
  /// CRITICAL risk or an exercise ui_action arrived during the turn
  /// (Prompt 29), or the crisis flow or a breathing run started during the
  /// turn or is still on screen / pending.
  bool _textOnlyTurn(ChatController chat) {
    final safety = ref.read(safetyControllerProvider);
    return chat.textOnlyEvents != _turnTextOnlyEvents ||
        safety.crisisCount != _turnCrisisCount ||
        safety.crisis != null ||
        safety.resolutionPending ||
        safety.breathing != null ||
        _turnBreathingId != null;
  }

  Future<void> _speakReply(String text) async {
    final uid = _uid;
    final companion = ref.read(selectedAvatarProvider).valueOrNull;
    // Unknown companion: no voice to pick.
    if (uid == null || companion == null) return;
    final aiId = _lastAiId;
    String? language;
    try {
      language = (await ref.read(settingsPrefsStoreProvider).load(uid))
          .language;
    } catch (_) {}
    // A newer reply, a send or a stop trigger got here first; never speak
    // into a recording.
    if (!mounted ||
        !_spokenReplies ||
        _turnOpen ||
        aiId != _lastAiId ||
        (_mic?.recording ?? false)) {
      return;
    }
    await _voice.speak(
      planSpeech(text, companion: companion, userLanguage: language),
    );
  }

  void _setTranscript(bool open) => setState(() => _transcriptOpen = open);

  /// Android back: closes the transcript first, then leaves (to Chat).
  void _onBack(bool didPop, Object? _) {
    if (!didPop && _transcriptOpen) _setTranscript(false);
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authServiceProvider.select((a) => a.user?.uid));
    // Signed out or another user (Prompt 29): nothing of this call may
    // keep running.
    ref.listen(authServiceProvider.select((a) => a.user?.uid), (prev, next) {
      if (prev == next) return;
      _stopVoiceAndMouth();
      unawaited(_mic?.interrupt());
      _camera.stop();
    });
    if (uid == null) return const SizedBox.shrink();
    final chat = ref.watch(chatControllerProvider(uid));
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final selected = ref.watch(selectedAvatarProvider);
    final mode = ref.watch(effectiveInputModeProvider);
    ref.listen(effectiveInputModeProvider, (prev, next) {
      if (prev != next) _onModeChanged();
    });
    ref.listen(selectedAvatarProvider, (prev, next) {
      _setModel(next);
      if (prev?.valueOrNull != next.valueOrNull) _stopVoice();
    });
    // The breathing screen opened or closed. Opening it discards a
    // recording in progress and closes the camera.
    ref.listen(safetyControllerProvider.select((s) => s.breathing != null), (
      _,
      open,
    ) {
      _stopVoice();
      if (open) {
        unawaited(_mic?.interrupt());
        _camera.stop();
      }
    });
    // companion-scene/page.tsx:18: the avatar only loads once the saved
    // companion is known and has a model (not Koi's fox).
    final showAvatar = selected.valueOrNull?.model != null;
    final mic = _mic;
    // Rebuilds when the crisis / breathing state changes.
    final safetyBlocks = ref.watch(
      safetyControllerProvider.select(
        (s) => s.crisis != null || s.resolutionPending || s.breathing != null,
      ),
    );
    final micBlocked = safetyBlocks || chat.isTyping;
    // Crisis flow opened (contract §3: stop any animation): back to idle,
    // neutral, no mouth movement; the camera closes.
    ref.listen(safetyControllerProvider.select((s) => s.crisisCount), (_, _) {
      _stopVoice();
      unawaited(_mic?.interrupt());
      _camera.stop();
      _avatar
        ..setMouthCues(const [])
        ..setConversationState(AvatarConversationState.idle)
        ..setEmotion(AvatarEmotion.neutral, 0);
    });
    // A pending resolution (crisis screen closed, path not yet sent) also
    // keeps the camera closed.
    ref.listen(
      safetyControllerProvider.select(
        (s) => s.crisis != null || s.resolutionPending,
      ),
      (_, blocked) {
        if (blocked) _camera.stop();
      },
    );

    return PopScope<Object?>(
      canPop: !_transcriptOpen,
      onPopInvokedWithResult: _onBack,
      // Background tint from the companion emotion (Prompt 27).
      child: EnvironmentBackground(
        strength: EnvironmentPalette.callStrength,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                _TopBar(
                  avatar: _avatar,
                  // companion-scene/page.tsx:19 companionName, shown instead
                  // of the avatar status when there is no avatar.
                  companionName: showAvatar
                      ? null
                      : selected.valueOrNull?.name ?? 'KOI',
                  transcriptOpen: _transcriptOpen,
                  onToggleTranscript: () => _setTranscript(!_transcriptOpen),
                ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: Padding(
                          // room for the 6px hard shadow
                          padding: const EdgeInsets.fromLTRB(16, 4, 22, 14),
                          child: showAvatar
                              ? AvatarView(
                                  controller: _avatar,
                                  source: ref.watch(avatarSourceProvider),
                                  pageFactory: ref.watch(
                                    avatarWebPageFactoryProvider,
                                  ),
                                  localHostFactory: ref.watch(
                                    avatarLocalHostFactoryProvider,
                                  ),
                                  // Chat never depends on the avatar: typing
                                  // and sending work while it loads, fails or
                                  // is ready.
                                  onReady: () {},
                                )
                              : _NoAvatarNotice(
                                  selected: selected,
                                  onReview: () {
                                    // The picker covers this screen.
                                    _camera.stop();
                                    reviewCompanionSelection(context, ref);
                                  },
                                ),
                        ),
                      ),
                      if (_voice.speaking case final kind?)
                        Positioned(
                          top: 14,
                          left: 28,
                          right: 34,
                          child: Center(child: _VoiceLabel(kind: kind)),
                        ),
                      if (mode.cameraView)
                        Positioned(
                          right: 32,
                          bottom: 24,
                          width: 120,
                          child: CameraPip(session: _camera),
                        ),
                      if (_transcriptOpen)
                        Positioned.fill(
                          child: _TranscriptPanel(
                            messages: chat.messages,
                            isTyping: chat.isTyping && !chat.isStreaming,
                            onClose: () => _setTranscript(false),
                          ),
                        ),
                    ],
                  ),
                ),
                if (mode.cameraView) const CameraDisclosureLine(),
                if (chat.holdingAudio ||
                    (mic != null &&
                        mic.sending &&
                        chat.backendStatus == BackendStatus.waking))
                  const WakingLine(),
                if (mic != null && mic.recording) MicRecordingStrip(mic: mic),
                if (mic != null) MicNoticeLine(mic: mic),
                // Typing is always available; only Send waits while a turn
                // (typed or voice, including the recording) is pending.
                InputBar(
                  onSend: chat.send,
                  disabled:
                      chat.isTyping ||
                      (mic != null && (mic.recording || mic.sending)),
                  keepTypingEnabled: true,
                  focusNode: _input,
                ),
                _CallControls(
                  compact: keyboardOpen,
                  showMic: mode.micInput && mic != null,
                  showCamera: mode.cameraView,
                  micRecording: mic?.recording ?? false,
                  micDisabled:
                      mic == null ||
                      mic.sending ||
                      (!mic.recording && micBlocked),
                  cameraOn: _camera.holdsCamera,
                  cameraDisabled: !_camera.holdsCamera && safetyBlocks,
                  onMic: _onMic,
                  onCamera: _onCamera,
                  onText: _onText,
                  onEnd: _endCall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// In place of the avatar while the saved companion loads, when it can't be
/// loaded, or for Koi's fox: web's notice (223e97c
/// companion-scene/page.tsx:33-41) and "Review companion selection".
class _NoAvatarNotice extends StatelessWidget {
  const _NoAvatarNotice({required this.selected, required this.onReview});

  final AsyncValue<CompanionAvatar> selected;
  final VoidCallback onReview;

  static const String loadingText = 'Loading your saved companion…';

  /// Web ends "…review your selection in onboarding."; mobile can't reopen
  /// onboarding, the link opens the companion picker instead.
  static const String errorText =
      'Your saved companion could not be loaded. Text conversation remains '
      'available; review your selection below.';
  static const String foxText =
      'Your saved Koi fox choice is preserved. This viewer currently '
      'supports the male and female VRM models; text conversation remains '
      'available.';
  static const String reviewLink = 'Review companion selection';

  @override
  Widget build(BuildContext context) {
    final String text = switch (selected) {
      AsyncError() => errorText,
      AsyncData() => foxText,
      _ => loadingText,
    };
    final review = selected is! AsyncLoading;
    final style = bodyText(14.4, weight: FontWeight.w600, height: 1.5);
    return Container(
      key: const Key('call-no-avatar'),
      decoration: BoxDecoration(
        color: KoiColors.neoYellow,
        border: Border.all(width: 3),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(offset: Offset(6, 6))],
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text, textAlign: TextAlign.center, style: style),
                if (review) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    link: true,
                    child: GestureDetector(
                      key: const Key('call-review-companion'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onReview,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            reviewLink,
                            style: style.copyWith(
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Status, the mode menu and the transcript toggle.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.avatar,
    required this.companionName,
    required this.transcriptOpen,
    required this.onToggleTranscript,
  });

  final AvatarViewController avatar;

  /// Shown instead of the avatar status when no avatar is loaded.
  final String? companionName;
  final bool transcriptOpen;
  final VoidCallback onToggleTranscript;

  /// At 360dp with "Hide transcript" this leaves the status 40+dp; longer
  /// labels ("Camera view + voice") ellipsize (the menu shows them whole).
  static const double _modeMaxWidth = 124;

  static const Map<AvatarStatus, String> statusText = {
    AvatarStatus.loading: 'Connecting…',
    AvatarStatus.ready: 'Connected',
    AvatarStatus.failed: 'Avatar offline',
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    child: Row(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: avatar,
            builder: (context, _) {
              return Text(
                companionName ?? statusText[avatar.status]!,
                key: const Key('call-status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: displayText(16),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        // The mode menu (Prompt 29), in place of the Prompt 25 voice pill.
        // Long labels ellipsize so the status keeps its room at 360dp.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _modeMaxWidth),
          child: const ModeSelector(),
        ),
        const SizedBox(width: 8),
        _Pill(
          key: const Key('transcript-toggle'),
          label: transcriptOpen ? 'Hide transcript' : 'Transcript',
          active: transcriptOpen,
          onTap: onToggleTranscript,
        ),
      ],
    ),
  );
}

/// Which voice is speaking, over the top of the avatar area.
class _VoiceLabel extends StatelessWidget {
  const _VoiceLabel({required this.kind});
  final VoiceKind kind;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      key: const Key('voice-label'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: KoiColors.neoWhite,
        border: Border.all(width: 2),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        kind == VoiceKind.server
            ? AvatarCallScreen.serverVoiceLabel
            : AvatarCallScreen.deviceVoiceLabel,
        textAlign: TextAlign.center,
        style: bodyText(12.8, weight: FontWeight.w600),
      ),
    ),
  );
}

/// White pill, 2.5px border, hard shadow; black when [active] (top-nav
/// active tab colours).
class _Pill extends StatefulWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: widget.active,
    child: GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        transform: Matrix4.translationValues(
          _pressed ? 2 : 0,
          _pressed ? 2 : 0,
          0,
        ),
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: widget.active ? KoiColors.neoBlack : KoiColors.neoWhite,
          border: Border.all(width: 2.5),
          borderRadius: BorderRadius.circular(9999),
          boxShadow: [
            BoxShadow(
              offset: _pressed ? const Offset(1, 1) : const Offset(3, 3),
            ),
          ],
        ),
        child: Text(
          widget.label,
          style: displayText(
            14.08,
            color: widget.active ? KoiColors.neoWhite : KoiColors.neoBlack,
          ),
        ),
      ),
    ),
  );
}

/// The conversation so far, over the lower part of the avatar area. Reuses
/// the Chat screen's MessageList (bubbles, typing indicator, auto-scroll).
class _TranscriptPanel extends StatelessWidget {
  const _TranscriptPanel({
    required this.messages,
    required this.isTyping,
    required this.onClose,
  });

  final List<ChatMessage> messages;
  final bool isTyping;
  final VoidCallback onClose;

  static const double _headerHeight = 44;

  /// Below this inner height there is no room for messages (keyboard open
  /// on a short phone): only the header shows, scaled down to fit.
  static const double _minWithList = _headerHeight + 2 + 48;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        key: const Key('transcript-panel'),
        // Lower 65% of the avatar; all of it when the area is small.
        height: c.maxHeight >= 240 ? c.maxHeight * 0.65 : c.maxHeight,
        margin: const EdgeInsets.fromLTRB(16, 0, 22, 14),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: KoiColors.neoWhite,
          border: Border.all(width: 3),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(offset: Offset(6, 6))],
        ),
        child: LayoutBuilder(
          builder: (context, inner) {
            final header = SizedBox(
              width: inner.maxWidth,
              height: _headerHeight,
              child: _header(),
            );
            if (inner.maxHeight < _minWithList) {
              return FittedBox(fit: BoxFit.scaleDown, child: header);
            }
            return Column(
              children: [
                header,
                Container(height: 2, color: KoiColors.neoBlack),
                Expanded(
                  child: messages.isEmpty && !isTyping
                      ? Center(
                          child: Text(
                            AvatarCallScreen.emptyTranscript,
                            style: bodyText(14, color: const Color(0xFF4B5563)),
                          ),
                        )
                      : MessageList(messages: messages, isTyping: isTyping),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _header() => Row(
    children: [
      const SizedBox(width: 16),
      Expanded(
        child: Text(
          'Transcript',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: displayText(16),
        ),
      ),
      Semantics(
        button: true,
        label: 'Close transcript',
        child: GestureDetector(
          key: const Key('transcript-close'),
          behavior: HitTestBehavior.opaque,
          onTap: onClose,
          child: SizedBox.square(
            dimension: _headerHeight,
            child: Center(
              child: StrokeIcon(
                paths: closeIconPaths,
                size: 20,
                strokeWidth: 2.5,
                color: KoiColors.neoBlack,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// Mic and camera (only in the modes that use them), text chat, end call.
class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.compact,
    required this.showMic,
    required this.showCamera,
    required this.micRecording,
    required this.micDisabled,
    required this.cameraOn,
    required this.cameraDisabled,
    required this.onMic,
    required this.onCamera,
    required this.onText,
    required this.onEnd,
  });

  /// Voice / Camera view + voice (Prompt 29: hidden otherwise).
  final bool showMic;

  /// Camera view / Camera view + voice (Prompt 29: hidden otherwise).
  final bool showCamera;

  /// Recording: the mic button is active and sends.
  final bool micRecording;

  /// Crisis / breathing open, a reply pending, or a voice message sending.
  final bool micDisabled;

  /// The camera is on (or starting): the button is active and turns it off.
  final bool cameraOn;

  /// Crisis / breathing open while the camera is off.
  final bool cameraDisabled;

  /// The keyboard is open (read above the Scaffold, which hides it from
  /// its body).
  final bool compact;
  final VoidCallback onMic, onCamera, onText, onEnd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (showMic)
          _CallButton(
            key: const Key('call-mic'),
            // Tap again to send (Prompt 26).
            label: micRecording ? 'Send' : 'Mic',
            paths: micIconPaths,
            active: micRecording,
            disabled: micDisabled,
            compact: compact,
            onTap: onMic,
          ),
        if (showCamera)
          _CallButton(
            key: const Key('call-camera'),
            // Start on tap, one tap off (Prompt 29).
            label: cameraOn ? 'Camera off' : 'Camera',
            paths: videoIconPaths,
            active: cameraOn,
            disabled: cameraDisabled,
            compact: compact,
            onTap: onCamera,
          ),
        _CallButton(
          key: const Key('call-text'),
          label: 'Chat',
          paths: chatIconPaths,
          active: false,
          compact: compact,
          onTap: onText,
        ),
        _CallButton(
          key: const Key('call-end'),
          label: 'End',
          paths: endCallIconPaths,
          active: false,
          compact: compact,
          danger: true,
          onTap: onEnd,
        ),
      ],
    ),
  );
}

/// 56dp round Neo button with a label underneath. Active = black fill,
/// white icon; danger = .neo-btn-danger red.
class _CallButton extends StatefulWidget {
  const _CallButton({
    super.key,
    required this.label,
    required this.paths,
    required this.active,
    required this.onTap,
    this.danger = false,
    this.disabled = false,
    required this.compact,
  });

  final String label;
  final List<Path> paths;
  final bool active;
  final bool danger;

  /// Greyed out; a tap still calls [onTap], which ignores it.
  final bool disabled;

  /// Keyboard open: no label under the button.
  final bool compact;
  final VoidCallback onTap;

  static const double size = 56;

  @override
  State<_CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends State<_CallButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.danger
        ? KoiColors.danger
        : widget.active
        ? KoiColors.neoBlack
        : KoiColors.neoWhite;
    final fg = widget.danger || widget.active
        ? KoiColors.neoWhite
        : KoiColors.neoBlack;
    return Semantics(
      button: true,
      label: widget.label,
      toggled: widget.danger || widget.disabled ? null : widget.active,
      enabled: widget.disabled ? false : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = !widget.disabled),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: Opacity(
          key: const Key('call-button-opacity'),
          opacity: widget.disabled ? 0.4 : 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: _CallButton.size,
                height: _CallButton.size,
                transform: Matrix4.translationValues(
                  _pressed ? 2 : 0,
                  _pressed ? 2 : 0,
                  0,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  border: Border.all(width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      offset: _pressed
                          ? const Offset(1, 1)
                          : const Offset(3, 3),
                    ),
                  ],
                ),
                child: StrokeIcon(
                  paths: widget.paths,
                  size: 24,
                  strokeWidth: 2.2,
                  color: fg,
                ),
              ),
              // No label while the keyboard is open, to leave room for the
              // avatar on short phones (Semantics keeps the label).
              if (!widget.compact) ...[
                const SizedBox(height: 6),
                Text(widget.label, style: displayText(12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
