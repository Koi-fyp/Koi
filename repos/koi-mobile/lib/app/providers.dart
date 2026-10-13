import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_service.dart';
import '../core/onboarding_store.dart';

/// Overridden in main.dart (and in tests) with a concrete implementation.
final authServiceProvider = ChangeNotifierProvider<AuthService>(
  (ref) => throw UnimplementedError('authServiceProvider must be overridden'),
);

/// Overridden in main.dart (and in tests) with the opened Hive box.
final onboardingStoreProvider = ChangeNotifierProvider<OnboardingStore>(
  (ref) =>
      throw UnimplementedError('onboardingStoreProvider must be overridden'),
);
