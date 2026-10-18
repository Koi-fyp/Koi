import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'checkin_models.dart';
import 'checkin_store.dart';

/// Overridden in main.dart with the `koi_checkins` Hive box.
final checkInBoxProvider = Provider<CheckInBox>((ref) => MemoryCheckInBox());

final checkInRepositoryProvider = Provider<CheckInRepository>(
  (ref) => CheckInRepository(
    box: ref.read(checkInBoxProvider),
    cipher: ref.read(messageCipherProvider),
    cryptoContext: ref.read(cryptoContextGetterProvider),
  ),
);

/// The check-in clock; tests override it.
final checkInClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Debug tools ("Add sample check-ins (debug)", "Clear check-ins (debug)")
/// only in debug builds; tests override it to check the release state.
final checkInDebugToolsProvider = Provider<bool>((ref) => kDebugMode);

/// One user's decrypted check-ins, shared by the Progress dashboard, the
/// calendar and the check-in screens.
class CheckInController extends ChangeNotifier {
  CheckInController(this.uid, this._repo) {
    reload();
  }

  final String uid;
  final CheckInRepository _repo;

  CheckInHistory _history = CheckInHistory.empty;
  bool _loading = true;
  bool _disposed = false;

  CheckInHistory get history => _history;
  bool get loading => _loading;

  Future<void> reload() async {
    try {
      final h = await _repo.load(uid);
      if (_disposed) return;
      _history = h;
    } catch (e) {
      debugPrint('KOI: check-ins not loaded: ${e.runtimeType}');
    }
    _loading = false;
    if (!_disposed) notifyListeners();
  }

  Future<MorningCheckIn> saveMorning({
    required DateTime now,
    required int sleep,
    required int mood,
    required int connection,
    required int energy,
    required CheckInEmotion emotion,
  }) async {
    final m = await _repo.saveMorning(
      uid,
      now: now,
      sleep: sleep,
      mood: mood,
      connection: connection,
      energy: energy,
      emotion: emotion,
    );
    await reload();
    return m;
  }

  Future<void> saveEvening({
    required DateTime now,
    required String text,
  }) async {
    await _repo.saveEvening(uid, now: now, text: text);
    await reload();
  }

  Future<void> markDone(MorningCheckIn m, CheckInActivity a) async {
    await _repo.saveMorningRecord(uid, m.withActivityDone(a));
    await reload();
  }

  Future<void> addSamples(DateTime now) async {
    await _repo.addSamples(uid, now);
    await reload();
  }

  Future<void> clear() async {
    await _repo.clear(uid);
    await reload();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final checkInControllerProvider =
    ChangeNotifierProvider.family<CheckInController, String>(
      (ref, uid) => CheckInController(uid, ref.read(checkInRepositoryProvider)),
    );
