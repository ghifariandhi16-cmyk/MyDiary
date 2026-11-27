import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

class AuthController {
  FirebaseAuth? _auth;

  Future<void> initialize() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    _auth = FirebaseAuth.instance;
  }

  Stream<User?> get authStateChanges => _requireAuth().authStateChanges();

  Future<void> signIn({required String email, required String password}) async {
    await _requireAuth().signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> register({
    required String email,
    required String password,
  }) async {
    await _requireAuth().createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> sendPasswordReset(String email) async {
    await _requireAuth().sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() => _requireAuth().signOut();

  FirebaseAuth _requireAuth() {
    final auth = _auth;
    if (auth == null) {
      throw StateError('Firebase belum siap. Periksa konfigurasi Firebase.');
    }
    return auth;
  }
}
