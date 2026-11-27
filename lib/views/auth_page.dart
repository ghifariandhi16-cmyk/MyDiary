import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../theme/app_colors.dart';

enum _AuthMode { signIn, register, forgotPassword }

class AuthPage extends StatefulWidget {
  final AuthController authController;
  final String? configurationError;

  const AuthPage({
    super.key,
    required this.authController,
    this.configurationError,
  });

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  _AuthMode _mode = _AuthMode.signIn;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });

    try {
      switch (_mode) {
        case _AuthMode.signIn:
          await widget.authController.signIn(
            email: _email.text,
            password: _password.text,
          );
          break;
        case _AuthMode.register:
          await widget.authController.register(
            email: _email.text,
            password: _password.text,
          );
          break;
        case _AuthMode.forgotPassword:
          await widget.authController.sendPasswordReset(_email.text);
          if (mounted) {
            setState(() {
              _message =
                  'Jika email terdaftar, tautan untuk mengatur ulang '
                  'password akan dikirim.';
            });
          }
          break;
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _error = _authErrorMessage(error));
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authErrorMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'invalid-email' => 'Format email tidak valid.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' => 'Email atau password tidak sesuai.',
      'email-already-in-use' => 'Email ini sudah terdaftar. Silakan masuk.',
      'weak-password' => 'Password minimal 6 karakter.',
      'user-disabled' => 'Akun ini dinonaktifkan.',
      'too-many-requests' => 'Terlalu banyak percobaan. Coba lagi nanti.',
      'network-request-failed' =>
        'Tidak ada koneksi internet. Periksa jaringan lalu coba lagi.',
      _ => error.message ?? 'Autentikasi gagal. Silakan coba lagi.',
    };
  }

  void _setMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _message = null;
    });
  }

  String get _title => switch (_mode) {
    _AuthMode.signIn => 'Masuk',
    _AuthMode.register => 'Buat akun',
    _AuthMode.forgotPassword => 'Lupa password?',
  };

  String get _subtitle => switch (_mode) {
    _AuthMode.signIn => 'Masuk untuk membuka diary pribadimu.',
    _AuthMode.register => 'Buat akun untuk mulai menyimpan ceritamu.',
    _AuthMode.forgotPassword =>
      'Masukkan email akunmu. Kami akan mengirim tautan reset password.',
  };

  String get _buttonLabel => switch (_mode) {
    _AuthMode.signIn => 'Masuk',
    _AuthMode.register => 'Daftar',
    _AuthMode.forgotPassword => 'Kirim tautan reset',
  };

  @override
  Widget build(BuildContext context) {
    final configurationError = widget.configurationError;

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE9FBF6), Color(0xFFFDFCF9), Color(0xFFD2F5F0)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: Column(
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF42D0A4), Color(0xFF4B9BE9)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: teal.withValues(alpha: .25),
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.auto_stories_rounded,
                        color: Colors.white,
                        size: 46,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'My Diary',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        color: deepTeal,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const Text(
                      'Private Journal',
                      style: TextStyle(
                        fontSize: 16,
                        letterSpacing: 3,
                        color: deepTeal,
                      ),
                    ),
                    const SizedBox(height: 34),
                    Card(
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _title,
                                style: const TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _subtitle,
                                style: const TextStyle(
                                  color: muted,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 22),
                              if (configurationError != null) ...[
                                _MessageBox(
                                  text: configurationError,
                                  isError: true,
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (_error != null) ...[
                                _MessageBox(text: _error!, isError: true),
                                const SizedBox(height: 16),
                              ],
                              if (_message != null) ...[
                                _MessageBox(text: _message!, isError: false),
                                const SizedBox(height: 16),
                              ],
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction:
                                    _mode == _AuthMode.forgotPassword
                                    ? TextInputAction.done
                                    : TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.email_outlined),
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  final email = value?.trim() ?? '';
                                  if (email.isEmpty || !email.contains('@')) {
                                    return 'Masukkan alamat email yang valid.';
                                  }
                                  return null;
                                },
                              ),
                              if (_mode != _AuthMode.forgotPassword) ...[
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _password,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: _mode == _AuthMode.register
                                      ? const [AutofillHints.newPassword]
                                      : const [AutofillHints.password],
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.key_rounded),
                                    suffixIcon: IconButton(
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                      ),
                                    ),
                                    border: const OutlineInputBorder(),
                                  ),
                                  validator: (value) {
                                    final password = value ?? '';
                                    if (password.isEmpty) {
                                      return 'Password wajib diisi.';
                                    }
                                    if (_mode == _AuthMode.register &&
                                        password.length < 6) {
                                      return 'Password minimal 6 karakter.';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                              if (_mode == _AuthMode.signIn)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _setMode(
                                            _AuthMode.forgotPassword,
                                          ),
                                    child: const Text('Lupa password?'),
                                  ),
                                ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 52,
                                child: FilledButton(
                                  onPressed: _busy || configurationError != null
                                      ? null
                                      : _submit,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: teal,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _busy
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          _buttonLabel,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_mode == _AuthMode.register)
                                TextButton(
                                  onPressed: () => _setMode(_AuthMode.signIn),
                                  child: const Text('Sudah punya akun? Masuk'),
                                )
                              else if (_mode != _AuthMode.signIn)
                                TextButton(
                                  onPressed: () => _setMode(_AuthMode.signIn),
                                  child: const Text('Kembali ke halaman masuk'),
                                )
                              else
                                TextButton(
                                  onPressed: () => _setMode(_AuthMode.register),
                                  child: const Text('Belum punya akun? Daftar'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBox extends StatelessWidget {
  final String text;
  final bool isError;

  const _MessageBox({required this.text, required this.isError});

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.red.shade700 : deepTeal;
    final background = isError
        ? const Color(0xFFFFF0EF)
        : const Color(0xFFE9FBF6);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
