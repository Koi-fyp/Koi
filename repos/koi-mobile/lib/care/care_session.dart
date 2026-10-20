import 'dart:async';

import 'package:flutter/foundation.dart';

import '../applications/application_api.dart';
import '../applications/application_models.dart';
import '../appointments/appointment_api.dart';
import '../appointments/appointment_models.dart';
import '../care_messages/message_api.dart';
import '../care_messages/message_models.dart';
import '../experts/expert_api.dart';
import '../notifications/notification_api.dart';
import '../notifications/notification_models.dart';
import '../platform/platform_client.dart';
import 'care_api_support.dart';
import 'care_strings.dart';

// MOB-2 state, per uid and IN MEMORY ONLY (decision C; contract semantics
// "persistent protected offline caches are disabled in the MVP"). A new
// CareSession is built for every signed-in uid (careSessionProvider), so
// an account switch or sign-out drops everything of the previous account.

/// A paged server list with a stale-while-revalidate cache: re-opening a
/// screen shows the last items at once with "Updating…" ([isUpdating])
/// until the server answers, then the server data replaces them.
///
/// MOB-4 (contract v0.5.2, community.ts / service.ts):
/// - pages come in document-id order, NOT by time (ids are hashes), so a
///   time-ordered list ([loadAll]) reads every page (at most [maxPages],
///   then [capped]) and sorts on the phone;
/// - a page can be empty and still have a next cursor (hidden directory
///   profiles are dropped server-side), so empty pages are skipped;
/// - a cursor is signed and expires after 15 minutes (or when the
///   relationship revision changes): its 422 restarts from the first page.
class CareList<T> extends ChangeNotifier {
  CareList(
    this._fetch, {
    required this.idOf,
    this.sort,
    this.loadAll = false,
    this.maxPages = careMaxPages,
  });

  final Future<ApiPage<T>> Function(String? cursor) _fetch;
  final String Function(T item) idOf;

  /// Optional client-side order (the contract does not state one).
  final int Function(T a, T b)? sort;

  /// Every refresh reads all pages (messages, appointments).
  final bool loadAll;
  final int maxPages;

  /// Empty pages followed in one call before giving up (never endless).
  static const int maxEmptyPages = 10;

  List<T> _items = const [];
  String? _nextCursor;
  bool _loaded = false;
  bool _busy = false;
  bool _loadingMore = false;
  bool _capped = false;
  Object? _error;
  int _gen = 0;
  bool _disposed = false;

  List<T> get items => _items;

  /// A "Show more" exists only for page-by-page lists.
  bool get hasMore => !loadAll && _nextCursor != null;
  bool get loaded => _loaded;

  /// [loadAll] stopped at [maxPages] with pages left: the screen says so
  /// instead of dropping them silently.
  bool get capped => _capped;

  /// Nothing to show yet and a request is running: full loading state.
  bool get isLoading => !_loaded && _busy;

  /// Showing cached data while the server is asked again.
  bool get isUpdating => _loaded && _busy;
  bool get isLoadingMore => _loadingMore;

  /// The last failure (null after a success).
  Object? get error => _error;

  /// First page again. [merge] keeps older pages already loaded (polling a
  /// message thread); otherwise the first page replaces the list.
  Future<void> refresh({bool merge = false}) async {
    final gen = ++_gen;
    _busy = true;
    // Screens start a refresh from initState: tell listeners after the
    // current build (the getters already report busy).
    scheduleMicrotask(_notify);
    try {
      ApiPage<T>? page;
      try {
        page = await _collect(null, gen);
      } catch (e) {
        // A cursor of this same read expired / went stale: start over once.
        if (!loadAll || !_isStaleCursor(e) || gen != _gen || _disposed) {
          rethrow;
        }
        page = await _collect(null, gen);
      }
      if (page == null) return;
      _items = _ordered(_merge(merge ? _items : const [], page.items));
      if (loadAll) {
        _nextCursor = null;
        _capped = page.nextCursor != null;
      } else if (!merge || !_loaded) {
        _nextCursor = page.nextCursor;
      }
      _loaded = true;
      _error = null;
    } catch (e) {
      if (gen != _gen || _disposed) return;
      _error = e;
    }
    _busy = false;
    _notify();
  }

  /// Refreshes only if nothing was loaded yet or the cache is shown.
  Future<void> ensure() => _busy ? Future.value() : refresh();

  Future<void> loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    final gen = _gen;
    _loadingMore = true;
    _notify();
    try {
      final page = await _collect(cursor, gen);
      if (page == null) {
        if (!_disposed) _loadingMore = false;
        return;
      }
      _items = _ordered(_merge(_items, page.items));
      _nextCursor = page.nextCursor;
      _error = null;
    } catch (e) {
      if (gen != _gen || _disposed) return;
      _loadingMore = false;
      // The cursor expired (15 minutes) or the list changed under it: the
      // first page again, never a dead "Show more".
      if (_isStaleCursor(e)) return refresh();
      _error = e;
    }
    _loadingMore = false;
    _notify();
  }

  /// From [cursor]: one page, following empty ones (at most
  /// [maxEmptyPages]); or, for [loadAll], every page up to [maxPages]. The
  /// result's cursor is where it stopped. Null = superseded.
  Future<ApiPage<T>?> _collect(String? cursor, int gen) async {
    final items = <T>[];
    var next = cursor;
    var fetches = 0;
    do {
      final page = await _fetch(next);
      if (gen != _gen || _disposed) return null;
      items.addAll(page.items);
      next = page.nextCursor;
      fetches++;
      final more = loadAll
          ? fetches < maxPages
          : items.isEmpty && fetches < maxEmptyPages;
      if (!more) break;
    } while (next != null);
    return ApiPage(items, next);
  }

  /// The server's 422 `invalid_request` for a cursor (service.ts:185-196).
  static bool _isStaleCursor(Object e) =>
      e is PlatformException && e.code == PlatformErrorCode.invalid;

  /// Puts the SERVER's answer for one item in place (or adds it).
  void put(T item) {
    _items = _ordered(_merge(_items, [item]));
    _notify();
  }

  void removeWhere(bool Function(T item) test) {
    _items = [
      for (final i in _items)
        if (!test(i)) i,
    ];
    _notify();
  }

  /// Drops every item and cancels in-flight answers.
  void clear() {
    _gen++;
    _items = const [];
    _nextCursor = null;
    _loaded = false;
    _busy = false;
    _loadingMore = false;
    _capped = false;
    _error = null;
    _notify();
  }

  List<T> _merge(List<T> old, List<T> fresh) {
    final byId = {for (final i in old) idOf(i): i};
    for (final i in fresh) {
      byId[idOf(i)] = i;
    }
    return byId.values.toList();
  }

  List<T> _ordered(List<T> list) {
    final s = sort;
    if (s == null) return list;
    return [...list]..sort(s);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    super.dispose();
  }
}

/// One professional conversation (one relationship).
class ThreadController extends ChangeNotifier {
  ThreadController({
    required this.api,
    required this.relationshipId,
    this.pollInterval = const Duration(seconds: 20),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    list = CareList<HumanMessage>(
      (cursor) => api.list(relationshipId, cursor: cursor),
      idOf: (m) => m.id,
      // Server pages are in id order: read them all, then oldest first.
      sort: (a, b) => a.createdAt.compareTo(b.createdAt),
      loadAll: true,
    )..addListener(notifyListeners);
  }

  final CareMessageApi api;
  final String relationshipId;
  final Duration pollInterval;
  final DateTime Function() _now;
  late final CareList<HumanMessage> list;

  List<OutgoingMessage> _outgoing = const [];
  Timer? _poll;
  int _localSeq = 0;
  bool _disposed = false;

  /// Oldest first.
  List<HumanMessage> get messages => list.items;

  /// Messages typed here and not confirmed by the server yet (pending or
  /// failed), oldest first.
  List<OutgoingMessage> get outgoing => _outgoing;
  bool get isPolling => _poll != null;

  /// While the thread is open: refresh now and every [pollInterval]
  /// (no websockets: the contract has none).
  void startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(pollInterval, (_) => list.refresh(merge: true));
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  /// Sends [body] (trimmed, max 4000). Returns the failure, or null.
  Future<CareFailure?> send(String body) {
    final text = body.trim();
    if (text.isEmpty || text.length > humanMessageMaxLength) {
      return Future.value(CareFailure.other);
    }
    final m = OutgoingMessage(
      localId: 'local-${_localSeq++}',
      body: text,
      idempotencyKey: newIdempotencyKey(),
      createdAt: _now().toUtc(),
    );
    _outgoing = [..._outgoing, m];
    notifyListeners();
    return _deliver(m);
  }

  /// "Failed — tap to retry": the SAME idempotency key, so a send that did
  /// reach the server is not posted twice.
  Future<CareFailure?> retry(String localId) {
    final i = _outgoing.indexWhere((m) => m.localId == localId);
    if (i < 0) return Future.value(null);
    final m = _outgoing[i].withStatus(OutgoingStatus.pending);
    _outgoing = [..._outgoing]..[i] = m;
    notifyListeners();
    return _deliver(m);
  }

  Future<CareFailure?> _deliver(OutgoingMessage m) async {
    try {
      final sent = await api.send(
        relationshipId,
        m.body,
        idempotencyKey: m.idempotencyKey,
      );
      if (_disposed) return null;
      _outgoing = [
        for (final o in _outgoing)
          if (o.localId != m.localId) o,
      ];
      list.put(sent);
      notifyListeners();
      return null;
    } catch (e) {
      if (_disposed) return null;
      _outgoing = [
        for (final o in _outgoing)
          o.localId == m.localId ? o.withStatus(OutgoingStatus.failed) : o,
      ];
      notifyListeners();
      return careFailureOf(e);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    list.dispose();
    super.dispose();
  }
}

/// Everything MOB-2 holds for ONE signed-in uid.
class CareSession extends ChangeNotifier {
  CareSession({
    required this.uid,
    required this.expertApi,
    required this.applicationApi,
    required this.messageApi,
    required this.appointmentApi,
    required this.notificationApi,
    this.refreshCapabilities,
    this.pollInterval = const Duration(seconds: 20),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    experts = CareList<ExpertProfile>(
      (cursor) => expertApi.list(cursor: cursor),
      idOf: (e) => e.id,
    )..addListener(notifyListeners);
    applications = CareList<ConnectionRequest>(
      (cursor) => applicationApi.list(cursor: cursor),
      idOf: (r) => r.id,
      sort: (a, b) => b.updatedAt.compareTo(a.updatedAt),
    )..addListener(notifyListeners);
    notifications = CareList<CareNotification>(
      (cursor) => notificationApi.list(cursor: cursor),
      // Stable event ids: a repeated delivery is shown once.
      idOf: (n) => n.eventId,
      sort: (a, b) => b.createdAt.compareTo(a.createdAt),
    )..addListener(_onNotifications);
  }

  final String uid;
  final ExpertDirectoryApi expertApi;
  final ApplicationApi applicationApi;
  final CareMessageApi messageApi;
  final AppointmentApi appointmentApi;
  final NotificationApi notificationApi;

  /// Re-checks `/me/capabilities` (silently). Called when an application
  /// outcome arrives, so an accepted application shows the Patient area.
  final Future<void> Function()? refreshCapabilities;
  final Duration pollInterval;
  final DateTime Function() _now;

  late final CareList<ExpertProfile> experts;
  late final CareList<ConnectionRequest> applications;
  late final CareList<CareNotification> notifications;
  final Map<String, ThreadController> _threads = {};
  final Map<String, CareList<Appointment>> _appointments = {};
  final Set<String> _seenApplicationEvents = {};
  bool _disposed = false;

  ThreadController thread(String relationshipId) => _threads.putIfAbsent(
    relationshipId,
    () => ThreadController(
      api: messageApi,
      relationshipId: relationshipId,
      pollInterval: pollInterval,
      now: _now,
    )..addListener(notifyListeners),
  );

  /// Threads already opened in this session (for the conversation list).
  ThreadController? existingThread(String relationshipId) =>
      _threads[relationshipId];

  CareList<Appointment> appointmentsFor(String relationshipId) =>
      _appointments.putIfAbsent(
        relationshipId,
        () => CareList<Appointment>(
          (cursor) => appointmentApi.list(relationshipId, cursor: cursor),
          idOf: (a) => a.id,
          sort: (a, b) => b.updatedAt.compareTo(a.updatedAt),
          loadAll: true,
        )..addListener(notifyListeners),
      );

  // ---- notifications ----

  int get unreadCount => notifications.items.where((n) => !n.isRead).length;

  /// Unread `new_message` notifications: the Care tab / conversation unread
  /// count (decision C: the contract has no message read state).
  List<CareNotification> get unreadMessageNotifications => [
    for (final n in notifications.items)
      if (!n.isRead && n.kind == NotificationKind.newMessage) n,
  ];

  /// Unread new_message notifications of one relationship: those whose
  /// message is in its loaded thread, or all of them when there is only
  /// one relationship ([onlyRelationship]).
  List<CareNotification> unreadMessagesFor(
    String relationshipId, {
    required bool onlyRelationship,
  }) {
    final unread = unreadMessageNotifications;
    if (onlyRelationship) return unread;
    final ids = {
      for (final m in _threads[relationshipId]?.messages ?? const []) m.id,
    };
    return [
      for (final n in unread)
        if (ids.contains(n.referenceId)) n,
    ];
  }

  /// Marks [n] read on the server; the list shows only the server's answer.
  Future<CareFailure?> markRead(CareNotification n) async {
    if (n.isRead) return null;
    try {
      final updated = await notificationApi.markRead(
        n.id,
        idempotencyKey: newIdempotencyKey(),
      );
      if (_disposed) return null;
      notifications.put(updated);
      return null;
    } catch (e) {
      return careFailureOf(e);
    }
  }

  /// No mark-all endpoint: one call per loaded unread item, one at a time.
  /// Stops at the first failure and returns it.
  Future<CareFailure?> markAllRead() async {
    for (final n in [...notifications.items.where((n) => !n.isRead)]) {
      final f = await markRead(n);
      if (f != null) return f;
      if (_disposed) return null;
    }
    return null;
  }

  Future<void> markMessagesRead(
    String relationshipId, {
    required bool onlyRelationship,
  }) async {
    for (final n in unreadMessagesFor(
      relationshipId,
      onlyRelationship: onlyRelationship,
    )) {
      if (await markRead(n) != null) return;
    }
  }

  void _onNotifications() {
    // An unread application outcome we have not reacted to yet: re-check
    // the capabilities once (accepted → the Patient area appears).
    var fresh = false;
    for (final n in notifications.items) {
      if (n.kind == NotificationKind.applicationState &&
          !n.isRead &&
          _seenApplicationEvents.add(n.eventId)) {
        fresh = true;
      }
    }
    if (fresh) {
      unawaited(refreshCapabilities?.call());
      unawaited(applications.loaded ? applications.refresh() : Future.value());
    }
    notifyListeners();
  }

  // ---- notice ----

  CareText? _notice;

  /// A calm one-line notice on the Care home (e.g. a screen closed because
  /// access was removed).
  CareText? get notice => _notice;

  void showNotice(CareText t) {
    _notice = t;
    notifyListeners();
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  // ---- lifecycle ----

  /// App back in the foreground: notifications and open threads again.
  void onResume() {
    if (_disposed) return;
    if (notifications.loaded) unawaited(notifications.refresh());
    for (final t in _threads.values) {
      if (t.isPolling) unawaited(t.list.refresh(merge: true));
    }
  }

  /// The patient relationship(s) ended: drop every cached professional
  /// message, appointment and patient notification at once.
  /// [keepRelationships] are still active (another practice).
  void clearPatientData({Set<String> keepRelationships = const {}}) {
    for (final id in [..._threads.keys]) {
      if (keepRelationships.contains(id)) continue;
      _threads.remove(id)!.dispose();
    }
    for (final id in [..._appointments.keys]) {
      if (keepRelationships.contains(id)) continue;
      _appointments.remove(id)!.dispose();
    }
    if (keepRelationships.isEmpty) {
      notifications.removeWhere(
        (n) => n.kind != NotificationKind.applicationState,
      );
    }
    notifyListeners();
  }

  bool get hasPatientData =>
      _threads.isNotEmpty ||
      _appointments.isNotEmpty ||
      notifications.items.any(
        (n) => n.kind != NotificationKind.applicationState,
      );

  @override
  void dispose() {
    _disposed = true;
    for (final t in _threads.values) {
      t.dispose();
    }
    for (final a in _appointments.values) {
      a.dispose();
    }
    _threads.clear();
    _appointments.clear();
    experts.dispose();
    applications.dispose();
    notifications.dispose();
    super.dispose();
  }
}
