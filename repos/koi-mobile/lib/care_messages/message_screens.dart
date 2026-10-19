import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../account/account_widgets.dart';
import '../account/capabilities.dart';
import '../account/capability_gate.dart';
import '../account/destinations.dart';
import '../care/care_api_support.dart';
import '../care/care_providers.dart';
import '../care/care_session.dart';
import '../care/care_strings.dart';
import '../care/care_widgets.dart';
import '../theme/koi_colors.dart';
import '../widgets/koi_loader.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_input.dart';
import 'message_models.dart';

// Professional messages: a clearly labelled human conversation, NOT the
// KOI companion chat. No companion chat widgets/providers, SSE, avatar,
// TTS or crisis pipeline are used here; the KOI crisis flow keeps working
// from the companion chat exactly as before.

String _psychologistName(WidgetRef ref, CareStrings s, RelationshipSummary r) =>
    ref.watch(psychologistNameProvider(r)).valueOrNull ??
    s.t(CareText.yourPsychologist);

/// The conversation list: one per active relationship.
class ConversationListScreen extends StatelessWidget {
  const ConversationListScreen({super.key});

  @override
  Widget build(BuildContext context) => CapabilityGate(
    destination: KoiDestination.messages,
    builder: (_) => const _ConversationList(),
  );
}

class _ConversationList extends ConsumerStatefulWidget {
  const _ConversationList();

  @override
  ConsumerState<_ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends ConsumerState<_ConversationList> {
  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final session = ref.read(careSessionProvider);
    final rels = ref.read(effectiveCapabilitiesProvider).activeRelationships;
    await Future.wait([
      for (final r in rels) session.thread(r.id).list.refresh(merge: true),
      session.notifications.refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(careStringsProvider);
    final session = ref.watch(careSessionProvider);
    final rels = ref.watch(effectiveCapabilitiesProvider).activeRelationships;
    return CarePage(
      demo: ref.watch(careMessageApiProvider).isMock,
      title: s.t(CareText.messages),
      onRefresh: _refresh,
      children: [
        if (rels.isEmpty)
          KoiNoticeCard(message: s.t(CareText.noConversations))
        else
          for (final r in rels)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _ConversationRow(
                relationship: r,
                thread: session.thread(r.id),
                unread: session
                    .unreadMessagesFor(r.id, onlyRelationship: rels.length == 1)
                    .length,
                strings: s,
              ),
            ),
      ],
    );
  }
}

class _ConversationRow extends ConsumerWidget {
  const _ConversationRow({
    required this.relationship,
    required this.thread,
    required this.unread,
    required this.strings,
  });

  final RelationshipSummary relationship;
  final ThreadController thread;
  final int unread;
  final CareStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings;
    final name = _psychologistName(ref, s, relationship);
    final last = thread.messages.lastOrNull;
    final list = thread.list;
    return CareCard(
      key: Key('conversation-${relationship.id}'),
      semanticsLabel: [
        s.messageTo(name),
        if (unread > 0) s.unreadCount(unread),
      ].join('. '),
      onTap: () => pushKoiPage<void>(
        context,
        MessageThreadScreen(relationshipId: relationship.id),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: careBody(s, size: 16.5, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                if (list.isLoading)
                  KoiLoader(compact: true, label: s.t(CareText.loading))
                else if (!list.loaded && list.error != null)
                  Text(careFailureText(s, list.error!), style: careMuted(s))
                else
                  Text(
                    last?.body ?? s.t(CareText.noMessagesYet),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: careMuted(s),
                  ),
                if (last != null)
                  Text(s.dateTime(last.createdAt), style: careMuted(s, 12)),
              ],
            ),
          ),
          if (unread > 0)
            Container(
              key: const Key('conversation-unread-dot'),
              width: 14,
              height: 14,
              margin: const EdgeInsetsDirectional.only(start: 8),
              decoration: BoxDecoration(
                color: KoiColors.neoBlue,
                shape: BoxShape.circle,
                border: Border.all(width: 2),
              ),
            ),
        ],
      ),
    );
  }
}

/// One professional conversation.
class MessageThreadScreen extends StatelessWidget {
  const MessageThreadScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context) => CapabilityGate(
    destination: KoiDestination.messageThread,
    builder: (_) => _Thread(relationshipId: relationshipId),
  );
}

class _Thread extends ConsumerStatefulWidget {
  const _Thread({required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<_Thread> createState() => _ThreadState();
}

class _ThreadState extends ConsumerState<_Thread> {
  final _text = TextEditingController();
  late final ThreadController _thread;
  late final CareSession _session;

  @override
  void initState() {
    super.initState();
    _session = ref.read(careSessionProvider);
    _thread = _session.thread(widget.relationshipId);
    unawaited(_open());
    _thread.startPolling();
  }

  Future<void> _open() async {
    await _thread.list.refresh(merge: true);
    if (!mounted) return;
    await _markRead();
  }

  /// Opening the thread marks its new_message notifications read.
  Future<void> _markRead() async {
    final rels = ref.read(effectiveCapabilitiesProvider).activeRelationships;
    if (!_session.notifications.loaded) await _session.notifications.refresh();
    await _session.markMessagesRead(
      widget.relationshipId,
      onlyRelationship: rels.length == 1,
    );
  }

  @override
  void dispose() {
    _thread.stopPolling();
    _text.dispose();
    super.dispose();
  }

  Future<void> _handle(Future<CareFailure?> attempt) async {
    final failure = await attempt;
    if (failure != CareFailure.reauth || !mounted) return;
    // Recent sign-in needed: re-check the password, then retry the SAME
    // message (same idempotency key). Never treated as lost access.
    if (!await showReauthSheet(context, ref)) return;
    final failed = _thread.outgoing
        .where((m) => m.status == OutgoingStatus.failed)
        .lastOrNull;
    if (failed != null) await _thread.retry(failed.localId);
  }

  void _send() {
    final body = _text.text;
    if (body.trim().isEmpty) return;
    _text.clear();
    unawaited(_handle(_thread.send(body)));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(careStringsProvider);
    final caps = ref.watch(effectiveCapabilitiesProvider);
    final rel = caps.activeRelationships
        .where((r) => r.id == widget.relationshipId)
        .firstOrNull;
    final name = rel == null
        ? s.t(CareText.yourPsychologist)
        : _psychologistName(ref, s, rel);
    return ListenableBuilder(
      listenable: _thread,
      builder: (context, _) {
        final list = _thread.list;
        return CarePage(
          demo: ref.watch(careMessageApiProvider).isMock,
          title: s.messageTo(name),
          onRefresh: () => list.refresh(merge: true),
          bottom: _Composer(controller: _text, strings: s, onSend: _send),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: CareChip(
                key: const Key('professional-message-label'),
                label: s.t(CareText.professionalMessage),
                color: KoiColors.neoWhite,
              ),
            ),
            const SizedBox(height: 14),
            if (list.hasMore)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: list.isLoadingMore
                    ? KoiLoader(compact: true, label: s.t(CareText.loading))
                    : NeoButton(
                        key: const Key('thread-load-older'),
                        variant: NeoButtonVariant.ghost,
                        fullWidth: true,
                        onPressed: list.loadMore,
                        child: CareButtonLabel(s.t(CareText.loadOlder)),
                      ),
              ),
            if (list.isUpdating) CareUpdating(strings: s),
            if (list.isLoading)
              NeoSkeletonList(label: s.t(CareText.loading))
            else if (!list.loaded && list.error != null)
              KoiNoticeCard(
                key: Key(
                  careFailureOf(list.error!) == CareFailure.notAvailable
                      ? 'care-not-available'
                      : 'care-error',
                ),
                message: careFailureText(s, list.error!),
                action: careFailureOf(list.error!) == CareFailure.notAvailable
                    ? null
                    : () => list.refresh(merge: true),
                actionLabel: s.t(CareText.retry),
              )
            else if (_thread.messages.isEmpty && _thread.outgoing.isEmpty)
              KoiNoticeCard(
                key: const Key('care-empty'),
                message: s.t(CareText.noMessagesYet),
              ),
            for (final m in _thread.messages)
              _Bubble(
                key: Key('message-${m.id}'),
                strings: s,
                mine: m.senderUid == _session.uid,
                body: m.body,
                meta: s.dateTime(m.createdAt),
              ),
            for (final m in _thread.outgoing)
              _Bubble(
                key: Key('outgoing-${m.localId}'),
                strings: s,
                mine: true,
                body: m.body,
                pending: m.status == OutgoingStatus.pending,
                failed: m.status == OutgoingStatus.failed,
                onRetry: m.status == OutgoingStatus.failed
                    ? () => unawaited(_handle(_thread.retry(m.localId)))
                    : null,
              ),
          ],
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.strings,
    required this.mine,
    required this.body,
    this.meta,
    this.pending = false,
    this.failed = false,
    this.onRetry,
  });

  final CareStrings strings;
  final bool mine;
  final String body;
  final String? meta;
  final bool pending;
  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? KoiColors.neoYellow : KoiColors.neoWhite,
        border: Border.all(width: 2),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(offset: Offset(3, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(body, style: careBody(s)),
          const SizedBox(height: 4),
          if (pending)
            KoiLoader(compact: true, label: s.t(CareText.messagePending))
          else if (failed)
            Text(
              s.t(CareText.messageFailed),
              key: const Key('message-failed'),
              style: careBody(s, size: 13, weight: FontWeight.w700),
            )
          else if (meta != null)
            Text(
              mine ? '${s.t(CareText.you)} · $meta' : meta!,
              style: careMuted(s, 12),
            ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: mine
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: onRetry == null
            ? bubble
            : Semantics(
                button: true,
                label: s.t(CareText.messageFailed),
                child: GestureDetector(
                  key: const Key('message-retry'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onRetry,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: koiMinTouch),
                    child: bubble,
                  ),
                ),
              ),
      ),
    );
  }
}

/// The static safety footer + the text composer.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.strings,
    required this.onSend,
  });

  final TextEditingController controller;
  final CareStrings strings;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    return Container(
      decoration: const BoxDecoration(
        color: KoiColors.background,
        border: Border(top: BorderSide(width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: false,
            child: Text(
              s.t(CareText.safetyFooter),
              key: const Key('thread-safety-footer'),
              style: careBody(s, size: 12.5, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: NeoInput(
                  key: const Key('thread-composer'),
                  placeholder: s.t(CareText.composerHint),
                  controller: controller,
                  multiline: true,
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: koiMinTouch,
                  minWidth: koiMinTouch,
                ),
                child: NeoButton(
                  key: const Key('thread-send'),
                  onPressed: onSend,
                  child: Text(s.t(CareText.send)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
