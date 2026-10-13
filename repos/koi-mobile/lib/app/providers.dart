import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_service.dart';
import '../core/onboarding_store.dart';
import '../onboarding/onboarding_service.dart';

/// Overridden in main.dart (and in tests) with a concrete implementation.
final authServiceProvider = ChangeNotifierProvider<AuthService>(
  (ref) => throw UnimplementedError('authServiceProvider must be overridden'),
);

/// Overridden in main.dart (and in tests) with the opened Hive box.
final onboardingStoreProvider = ChangeNotifierProvider<OnboardingStore>(
  (ref) =>
      throw UnimplementedError('onboardingStoreProvider must be overridden'),
);

/// Overridden in main.dart (flutter_lib UserRepository) and in tests.
final onboardingUserWriterProvider = Provider<OnboardingUserWriter>(
  (ref) => throw UnimplementedError(
    'onboardingUserWriterProvider must be overridden',
  ),
);

final onboardingServiceProvider = Provider<OnboardingService>(
  (ref) => OnboardingService(
    flag: ref.read(onboardingStoreProvider),
    users: ref.read(onboardingUserWriterProvider),
    currentUid: () => ref.read(authServiceProvider).user?.uid,
  ),
);
