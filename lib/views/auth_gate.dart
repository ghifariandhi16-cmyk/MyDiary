import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import 'auth_page.dart';
import 'home_page.dart';

class AuthGate extends StatefulWidget {
  final AuthController? authController;

  const AuthGate({super.key, this.authController});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthController _authController;
  late final Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _authController = widget.authController ?? AuthController();
    _initialization = _authController.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, initialization) {
        if (initialization.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (initialization.hasError) {
          return AuthPage(
            authController: _authController,
            configurationError:
                'Firebase belum dikonfigurasi. Jalankan '
                '`flutterfire configure`, lalu coba lagi. '
                'Detail: ${initialization.error}',
          );
        }

        return StreamBuilder<User?>(
          stream: _authController.authStateChanges,
          builder: (context, authState) {
            if (authState.hasError) {
              return AuthPage(
                authController: _authController,
                configurationError:
                    'Tidak dapat memeriksa status akun: ${authState.error}',
              );
            }
            if (authState.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final user = authState.data;
            if (user == null) {
              return AuthPage(authController: _authController);
            }
            return HomePage(
              authController: _authController,
              userId: user.uid,
              email: user.email ?? '',
              userName: user.displayName ?? user.email ?? 'Diary User',
            );
          },
        );
      },
    );
  }
}
