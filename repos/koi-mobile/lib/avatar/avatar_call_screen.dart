import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../chat/chat_controller.dart';
import '../chat/widgets/chat_widgets.dart';
import '../onboarding/step_layout.dart';
import '../safety/safety_providers.dart';
import '../settings/widgets/avatar_picker.dart' show reviewCompanionSelection;
import '../settings/widgets/settings_widgets.dart'
    show SettingsToastLayer, ToastMessage, ToastType;
import '../theme/koi_colors.dart';
import 'avatar_providers.dart';
import 'avatar_view.dart';
import 'call_icons.dart';
import 'call_inputs.dart';

/// Video-call style conversation with the avatar. Mobile-only: there is no
/// web version of this screen yet, so the layout follows the Prompt 10 spec
/// and reuses the Chat screen's pieces (chatControllerProvider for messages
/// and sending, MessageList, InputBar, the Neo card/shadow styling, the
/// Toast).
///
/// Top to bottom: a bar with the transcript toggle, the avatar filling the
/// rest (transcript panel slides over its lower part when open), the
/// InputBar while text is the active input, and the call controls.
class AvatarCallScreen extends ConsumerStatefulWidget {
  const AvatarCallScreen({super.key, this.avatarController});

  /// Tests pass one to drive the avatar (fail, set emotion); otherwise the
  /// screen owns its own.
  final AvatarViewController? avatarController;

  /// Mobile-only toast texts (same "coming soon" toast as Settings/Progress).
  static const String voiceSoon = 'Voice coming soon!';
  static const String cameraSoon = 'Camera coming soon!';
  static const String emptyTranscript = 'No messages yet.';

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

  CallInputs _inputs = CallInputs.initial;
  bool _transcriptOpen = false;
  ToastMessage? _toast;
  int _toastSeq = 0;

  @override
  void initState() {
    super.initState();
    _setModel(ref.read(selectedAvatarProvider));
    _stateSource = ref.read(avatarStateSourceFactoryProvider)();
    _stateSub = _stateSource.events.listen(_avatar.apply);
  }

  @override
  void dispose() {
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

  void _soon(String message) => setState(
    () => _toast = ToastMessage(message, ToastType.info, ++_toastSeq),
  );

  // Voice and camera aren't available yet: the buttons are greyed out and
  // only show the coming-soon toast (no permission request, no preview).
  // CallInputs keeps the four approved modes for when they are.
  void _onMic() => _soon(AvatarCallScreen.voiceSoon);

  void _onText() {
    setState(() => _inputs = _inputs.selectText());
    // Typing never waits for the avatar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _input.requestFocus();
    });
  }

  void _onCamera() => _soon(AvatarCallScreen.cameraSoon);

  void _endCall() => Navigator.of(context).pop();

  void _setTranscript(bool open) => setState(() => _transcriptOpen = open);

  /// Android back: closes the transcript first, then leaves (to Chat).
  void _onBack(bool didPop, Object? _) {
    if (!didPop && _transcriptOpen) _setTranscript(false);
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authServiceProvider.select((a) => a.user?.uid));
    if (uid == null) return const SizedBox.shrink();
    final chat = ref.watch(chatControllerProvider(uid));
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final selected = ref.watch(selectedAvatarProvider);
    ref.listen(selectedAvatarProvider, (_, next) => _setModel(next));
    // companion-scene/page.tsx:18: the avatar only loads once the saved
    // companion is known and has a model (not Koi's fox).
    final showAvatar = selected.valueOrNull?.model != null;
    // Crisis flow opened (contract §3: stop any animation): back to idle,
    // neutral, no mouth movement.
    ref.listen(safetyControllerProvider.select((s) => s.crisisCount), (_, _) {
      _avatar
        ..setMouthCues(const [])
        ..setConversationState(AvatarConversationState.idle)
        ..setEmotion(AvatarEmotion.neutral, 0);
    });

    return PopScope<Object?>(
      canPop: !_transcriptOpen,
      onPopInvokedWithResult: _onBack,
      child: Scaffold(
        backgroundColor: KoiColors.background,
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
                  // Fill the area: the toast layer is the only
                  // non-positioned child and is empty most of the time.
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
                                // Chat never depends on the avatar: typing
                                // and sending work while it loads, fails or
                                // is ready.
                                onReady: () {},
                              )
                            : _NoAvatarNotice(
                                selected: selected,
                                onReview: () =>
                                    reviewCompanionSelection(context, ref),
                              ),
                      ),
                    ),
                    if (_transcriptOpen)
                      Positioned.fill(
                        child: _TranscriptPanel(
                          messages: chat.messages,
                          isTyping: chat.isTyping && !chat.isStreaming,
                          onClose: () => _setTranscript(false),
                        ),
                      ),
                    SettingsToastLayer(
                      toast: _toast,
                      onClose: () => setState(() => _toast = null),
                    ),
                  ],
                ),
              ),
              if (_inputs.textOn)
                InputBar(
                  onSend: chat.send,
                  disabled: chat.isTyping,
                  keepTypingEnabled: true,
                  focusNode: _input,
                ),
              _CallControls(
                compact: keyboardOpen,
                inputs: _inputs,
                onMic: _onMic,
                onCamera: _onCamera,
                onText: _onText,
                onEnd: _endCall,
              ),
            ],
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

/// Status + the transcript toggle.
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

/// Mic, camera, text chat, end call.
class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.inputs,
    required this.compact,
    required this.onMic,
    required this.onCamera,
    required this.onText,
    required this.onEnd,
  });

  final CallInputs inputs;

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
        _CallButton(
          key: const Key('call-mic'),
          label: 'Mic',
          paths: micIconPaths,
          active: false,
          disabled: true,
          compact: compact,
          onTap: onMic,
        ),
        _CallButton(
          key: const Key('call-camera'),
          label: 'Camera',
          paths: videoIconPaths,
          active: false,
          disabled: true,
          compact: compact,
          onTap: onCamera,
        ),
        _CallButton(
          key: const Key('call-text'),
          label: 'Chat',
          paths: chatIconPaths,
          active: inputs.textOn,
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

  /// Not available yet: greyed out; a tap still calls [onTap] (the
  /// coming-soon toast).
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
      hint: widget.disabled ? 'Coming soon' : null,
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
