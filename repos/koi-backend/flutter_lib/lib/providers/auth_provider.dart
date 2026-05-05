import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((ref) {
  final svc = ref.watch(authServiceProvider);
  return AuthStateNotifier(svc);
});

class AuthState {
  final bool loading;
  final String? userId;
  final String? error;

  AuthState({this.loading = false, this.userId, this.error});

  AuthState copyWith({bool? loading, String? userId, String? error}) {
    return AuthState(
      loading: loading ?? this.loading,
      userId: userId ?? this.userId,
      error: error ?? this.error,
    );
  }
}

class AuthStateNotifier extends StateNotifier<AuthState> {
  final AuthService _service;

  AuthStateNotifier(this._service) : super(AuthState()) {
    _init();
  }

  Future<void> _init() async {
    state = state.copyWith(loading: true);
    final auth = await _service.isAuthenticated();
    if (auth) {
      state = state.copyWith(loading: false, userId: _service.getCurrentUser()?.uid);
    } else {
      state = state.copyWith(loading: false);
    }
  }

  Future<void> signInAnonymously() async {
    state = state.copyWith(loading: true);
    final res = await _service.signInAnonymously();
    if (res.success) {
      state = state.copyWith(loading: false, userId: res.userId);
    } else {
      state = state.copyWith(loading: false, error: res.message);
    }
  }

  Future<void> linkWithEmail(String email, String password) async {
    state = state.copyWith(loading: true);
    final res = await _service.linkWithEmailAndPassword(email, password);
    if (res.success) {
      state = state.copyWith(loading: false, userId: res.userId);
    } else {
      state = state.copyWith(loading: false, error: res.message);
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(loading: true);
    await _service.signOut();
    state = AuthState(loading: false);
  }
}
