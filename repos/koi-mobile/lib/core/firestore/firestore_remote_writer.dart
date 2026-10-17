import 'package:cloud_firestore/cloud_firestore.dart';

import '../crypto_context.dart';
import '../sync_queue.dart';
import 'user_document_store.dart';

/// Converts a queued item's data for Firestore: the keys listed in
/// [SyncItem.timestampFields] go from ISO-8601 strings to `Timestamp`s.
Map<String, Object?> firestoreData(SyncItem item) => {
  for (final e in item.data.entries)
    e.key: item.timestampFields.contains(e.key) && e.value is String
        ? Timestamp.fromDate(DateTime.parse(e.value! as String))
        : e.value,
};

/// The real [RemoteWriter]. Ready once Firebase is set up and a user is
/// signed in; writes only items under that user's users/{uid}.
class FirestoreRemoteWriter implements RemoteWriter {
  FirestoreRemoteWriter({
    required FirebaseFirestore firestore,
    required this.currentUid,
    required this.userDocs,
    required this.saltCache,
  }) : _db = firestore;

  final FirebaseFirestore _db;
  final String? Function() currentUid;
  final UserDocumentStore userDocs;
  final SaltCache saltCache;

  @override
  bool get isReady => currentUid() != null;

  @override
  bool owns(SyncItem item) {
    final uid = currentUid();
    return uid != null && item.ownerUid == uid;
  }

  @override
  Future<void> write(SyncItem item) async {
    switch (item.op) {
      case SyncOp.merge:
        await _db
            .collection(item.collection)
            .doc(item.docId)
            .set(firestoreData(item), SetOptions(merge: true))
            .timeout(firestoreTimeout);
      case SyncOp.saltCreateOnce:
        final local = saltFromUserData(item.data);
        if (local == null) return; // malformed item: nothing to write
        final winner = await userDocs.createSaltOnce(item.docId, local);
        // Firestore's salt wins over the one generated offline.
        await saltCache.adopt(item.docId, winner);
    }
  }
}
