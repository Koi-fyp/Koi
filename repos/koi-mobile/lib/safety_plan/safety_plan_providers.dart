import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'safety_plan_models.dart';
import 'safety_plan_store.dart';

/// Overridden in main.dart with the `koi_safety_plan` Hive box.
final safetyPlanBoxProvider = Provider<SafetyPlanBox>(
  (ref) => MemorySafetyPlanBox(),
);

final safetyPlanRepositoryProvider = Provider<SafetyPlanRepository>(
  (ref) => SafetyPlanRepository(
    box: ref.read(safetyPlanBoxProvider),
    cipher: ref.read(messageCipherProvider),
    cryptoContext: ref.read(cryptoContextGetterProvider),
  ),
);

/// The safety plan clock; tests override it.
final safetyPlanClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// "Fill demo safety plan" / "Clear safety plan" in the DEBUG menu: debug
/// builds only; tests override it to check the release state.
final safetyPlanDebugToolsProvider = Provider<bool>((ref) => kDebugMode);

/// One user's decrypted plan. Per uid and auto-disposed, so a sign-out or
/// account switch drops the decrypted plan from memory and the next
/// account only ever reads its own row.
class SafetyPlanController extends ChangeNotifier {
  SafetyPlanController(this.uid, this._repo, this._now) {
    reload();
  }

  final String uid;
  final SafetyPlanRepository _repo;
  final DateTime Function() _now;

  SafetyPlan? _plan;
  bool _loading = true;
  bool _unreadable = false;
  bool _disposed = false;

  /// Null when there is no plan (or it could not be read).
  SafetyPlan? get plan => _plan;
  bool get loading => _loading;

  /// A stored plan exists but could not be opened (never shown half-read).
  bool get unreadable => _unreadable;

  /// True once loaded with at least one item the user wrote.
  bool get hasPlan => !_loading && !(_plan?.isEmpty ?? true);

  Future<void> reload() async {
    SafetyPlan? p;
    try {
      p = await _repo.load(uid);
    } catch (e) {
      debugPrint('KOI: safety plan not loaded: ${e.runtimeType}');
    }
    if (_disposed) return;
    _plan = p;
    _unreadable = p == null && _repo.hasRow(uid);
    _loading = false;
    notifyListeners();
  }

  /// Throws when it could not be saved (the editor says so).
  Future<void> save(SafetyPlan plan) async {
    final saved = await _repo.save(uid, plan, _now());
    if (_disposed) return;
    _plan = saved.isEmpty ? null : saved;
    _unreadable = false;
    _loading = false;
    notifyListeners();
  }

  Future<void> fillDemo() async {
    await _repo.fillDemo(uid, _now());
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

final safetyPlanControllerProvider = ChangeNotifierProvider.autoDispose
    .family<SafetyPlanController, String>(
      (ref, uid) => SafetyPlanController(
        uid,
        ref.read(safetyPlanRepositoryProvider),
        ref.read(safetyPlanClockProvider),
      ),
    );

/// The signed-in uid, or null.
final safetyPlanUidProvider = Provider.autoDispose<String?>(
  (ref) => ref.watch(authServiceProvider.select((a) => a.user?.uid)),
);
