import 'package:cloud_firestore/cloud_firestore.dart';

import '../crypto_context.dart';

/// Every Firestore call made by the app is cut off after this long and
/// treated as a failure (the sync queue then keeps the item). Firestore's
/// own offline cache is off (main.dart), so without a server answer a
/// write would otherwise never finish.
const Duration firestoreTimeout = Duration(seconds: 10);

/// The users/{uid} document a new user starts with. Same fields and values
/// as web's POST /api/auth/anonymous
/// (repos/koi-backend/nextjs_app/src/app/api/auth/anonymous/route.ts), which
/// writes it with the Admin SDK. Mobile signs in with Firebase anonymous
/// auth instead, so it writes the document itself.
Map<String, Object?> newUserDocument(String uid) => {
  'koiUuid': uid,
  'createdAt': FieldValue.serverTimestamp(),
  'lastActive': FieldValue.serverTimestamp(),
  'profile': {'avatar': null, 'language': 'en', 'notificationTime': null},
  'classification': <String, Object?>{},
  'settings': {
    'notifications_enabled': true,
    'sound_enabled': true,
    'haptic_enabled': true,
  },
  'stats': {
    'total_conversations': 0,
    'total_check_ins': 0,
    'current_streak': 0,
    'longest_streak': 0,
    'jigsaw_pieces': 0,
  },
};

/// Reads and writes users/{uid}. Both writes are Firestore transactions that
/// never overwrite a value that is already there.
class UserDocumentStore {
  UserDocumentStore(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('users').doc(uid);

  /// Creates users/{uid} with [newUserDocument] if it is missing. If it
  /// exists (possibly partial, e.g. an onboarding or salt merge got there
  /// first), only the missing top-level keys are added.
  Future<void> ensureCreated(String uid) => _db
      .runTransaction((tx) async {
        final ref = _ref(uid);
        final snapshot = await tx.get(ref);
        final fresh = newUserDocument(uid);
        if (!snapshot.exists) {
          tx.set(ref, fresh);
          return;
        }
        final data = snapshot.data() ?? const {};
        final missing = {
          for (final e in fresh.entries)
            if (!data.containsKey(e.key)) e.key: e.value,
        };
        // update() adds only these top-level keys and leaves the rest alone.
        if (missing.isNotEmpty) tx.update(ref, missing);
      }, timeout: firestoreTimeout)
      .timeout(firestoreTimeout);

  /// Salt create-once (we are the only writer of it). Returns the salt that
  /// Firestore holds afterwards: the existing one if there is one, otherwise
  /// [candidate], which this call stored.
  Future<String> createSaltOnce(String uid, String candidate) => _db
      .runTransaction((tx) async {
        final ref = _ref(uid);
        final snapshot = await tx.get(ref);
        final existing = saltFromUserData(snapshot.data());
        if (existing != null) return existing;
        // public_crypto_metadata holds only `salt` (rules), and there is no
        // salt yet, so writing the whole map loses nothing. update() keeps
        // every other field of an existing document.
        final salt = {
          'public_crypto_metadata': {'salt': candidate},
        };
        if (snapshot.exists) {
          tx.update(ref, salt);
        } else {
          tx.set(ref, salt);
        }
        return candidate;
      }, timeout: firestoreTimeout)
      .timeout(firestoreTimeout);

  /// crypto.ts: `getDoc(doc(firestore, 'users', uid))` → salt or null.
  Future<String?> fetchSalt(String uid) async => saltFromUserData(
    (await _ref(uid).get().timeout(firestoreTimeout)).data(),
  );
}
