import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:koi_flutter_lib/storage/hive_manager.dart';

import '../chat/message_record.dart';
import '../core/auth/debug_local_auth_service.dart';
import '../core/onboarding_store.dart';
import '../core/sync_queue.dart';

/// The app's own Hive boxes, all opened as `Box<String>`.
const List<String> _appBoxNames = [
  HiveMessageStore.boxName,
  OnboardingStore.boxName,
  DebugLocalAuthService.boxName,
  PersistentSyncQueue.boxName,
];

/// Every Hive box KOI opens: flutter_lib's (HiveManager) and the app's own.
/// All live in the one Hive folder (both call Hive.initFlutter()).
const List<String> koiHiveBoxNames = [
  HiveManager.usersBox,
  HiveManager.messagesBox,
  HiveManager.moodEntriesBox,
  HiveManager.cbtSessionsBox,
  HiveManager.tasksBox,
  ..._appBoxNames,
];

/// Total size in bytes of the `.hive` files of [koiHiveBoxNames], or null
/// when none of the app's boxes is open (so the folder is unknown) or the
/// files can't be read.
///
/// Web settings shows navigator.storage.estimate() (223e97c
/// hooks/useStorageEstimate.ts); mobile has no such quota, so it measures
/// KOI's own saved records instead. App files, the avatar and caches are not
/// counted.
Future<int?> koiHiveBytes() async {
  try {
    String? folder;
    for (final name in _appBoxNames) {
      // Hive.box needs the exact value type the box was opened with.
      if (!Hive.isBoxOpen(name)) continue;
      final path = Hive.box<String>(name).path;
      if (path != null) {
        folder = File(path).parent.path;
        break;
      }
    }
    if (folder == null) return null;
    var total = 0;
    for (final name in koiHiveBoxNames) {
      // Hive names each box file '<lowercase name>.hive'.
      final file = File(
        '$folder${Platform.pathSeparator}${name.toLowerCase()}.hive',
      );
      if (await file.exists()) total += await file.length();
    }
    return total;
  } catch (e) {
    debugPrint('KOI: storage size unavailable: ${e.runtimeType}');
    return null;
  }
}

/// KOI's on-device data size for the Settings storage card. Overridden in
/// tests.
final koiStorageBytesProvider = FutureProvider.autoDispose<int?>(
  (ref) => koiHiveBytes(),
);
