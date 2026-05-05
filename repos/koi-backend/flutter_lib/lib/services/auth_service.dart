import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:meta/meta.dart';
import '../models/user_model.dart';

class AuthResult {
  final bool success;
  final String? userId;
  final String? message;

  AuthResult({required this.success, this.userId, this.message});
}

class AuthService {
  final fb_auth.FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
  final FlutterSecureStorage _secureStorage;
  final Uuid _uuid;

  static const String _storageKey = 'koi_user_uuid';

  AuthService({
    fb_auth.FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FlutterSecureStorage? secureStorage,
    Uuid? uuid,
  })  : _auth = auth,
        _firestore = firestore,
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _uuid = uuid ?? const Uuid();

  Future<AuthResult> signInAnonymously() async {
    try {
      // Try to restore session first
      final storedUuid = await _secureStorage.read(key: _storageKey);
      final auth = _auth ?? fb_auth.FirebaseAuth.instance;
      fb_auth.User? user = auth.currentUser;

      if (user == null) {
        final cred = await auth.signInAnonymously();
        user = cred.user;
      }

      // Ensure we have a local koiUuid and it's persisted
      final koiUuid = storedUuid ?? _uuid.v4();
      await _secureStorage.write(key: _storageKey, value: koiUuid);

      // Create user document if missing
      if (user != null) {
        await createUserDocument(user.uid, koiUuid: koiUuid);
        return AuthResult(success: true, userId: user.uid);
      }

      return AuthResult(success: false, message: 'Failed to sign in anonymously');
    } on FirebaseException catch (e) {
      return _handleFirebaseException(e);
    } catch (e) {
      return AuthResult(success: false, message: e.toString());
    }
  }

  User? getCurrentUser() {
    final auth = _auth ?? fb_auth.FirebaseAuth.instance;
    final u = auth.currentUser;
    if (u == null) return null;
    return User(uid: u.uid);
  }

  Future<bool> isAuthenticated() async {
    final auth = _auth ?? fb_auth.FirebaseAuth.instance;
    final current = auth.currentUser;
    if (current != null) return true;
    final stored = await _secureStorage.read(key: _storageKey);
    return stored != null;
  }

  Future<void> signOut() async {
    // Keep local data for privacy and offline access
    final auth = _auth ?? fb_auth.FirebaseAuth.instance;
    await auth.signOut();
  }

  Future<AuthResult> linkWithEmailAndPassword(String email, String password) async {
    try {
      final auth = _auth ?? fb_auth.FirebaseAuth.instance;
      final firestore = _firestore ?? FirebaseFirestore.instance;

      final user = auth.currentUser;
      if (user == null) return AuthResult(success: false, message: 'Not authenticated');

      final credential = fb_auth.EmailAuthProvider.credential(email: email, password: password);
      final userCredential = await user.linkWithCredential(credential);

      // After linking send email verification
      await userCredential.user?.sendEmailVerification();

      // Preserve koiUuid in Firestore (it was stored earlier)
      final koiUuid = await _secureStorage.read(key: _storageKey);
      if (koiUuid != null) {
        await firestore.collection('users').doc(user.uid).set({
          'koiUuid': koiUuid,
          'email': email,
          'emailVerified': userCredential.user?.emailVerified ?? false,
        }, SetOptions(merge: true));
      }

      return AuthResult(success: true, userId: user.uid);
    } on FirebaseException catch (e) {
      // If invalid credentials, clear storage and restart flow
      if (e.code == 'invalid-credential' || e.code == 'wrong-password') {
        await _secureStorage.delete(key: _storageKey);
      }
      return _handleFirebaseException(e);
    } catch (e) {
      return AuthResult(success: false, message: e.toString());
    }
  }

  Future<String?> restoreSession() async {
    try {
      final koiUuid = await _secureStorage.read(key: _storageKey);
      return koiUuid;
    } catch (_) {
      return null;
    }
  }

  Future<void> createUserDocument(String userId, {required String koiUuid}) async {
    final firestore = _firestore ?? FirebaseFirestore.instance;
    final doc = firestore.collection('users').doc(userId);
    final snapshot = await doc.get();
    if (!snapshot.exists) {
      final user = KoiUser(uid: userId, koiUuid: koiUuid);
      await doc.set(user.toMap());
    } else {
      // Ensure koiUuid exists
      final data = snapshot.data();
      if (data != null && (data['koiUuid'] == null || data['koiUuid'] == '')) {
        await doc.set({'koiUuid': koiUuid}, SetOptions(merge: true));
      }
    }
  }

  AuthResult _handleFirebaseException(FirebaseException e) {
    if (e.code.contains('network')) {
      return AuthResult(success: false, message: 'Network error: ${e.message}');
    }
    if (e.code == 'quota-exceeded') {
      return AuthResult(success: false, message: 'Service temporarily unavailable (quota)');
    }
    if (e.code == 'user-disabled') {
      return AuthResult(success: false, message: 'Account disabled. Contact support.');
    }
    return AuthResult(success: false, message: e.message);
  }
}

// Minimal User wrapper to avoid importing firebase-auth types elsewhere
class User {
  final String uid;
  User({required this.uid});
}
