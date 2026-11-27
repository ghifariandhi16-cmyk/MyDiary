// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_diary/main.dart';
import 'package:my_diary/controllers/auth_controller.dart';

class _TestAuthController extends AuthController {
  @override
  Future<void> initialize() async {}

  @override
  Stream<User?> get authStateChanges => Stream<User?>.value(null);
}

void main() {
  testWidgets('app displays sign-in, registration, and reset forms', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyDiaryApp(authController: _TestAuthController()));
    await tester.pumpAndSettle();

    expect(find.text('My Diary'), findsOneWidget);
    expect(find.text('Private Journal'), findsOneWidget);
    expect(find.text('Masuk'), findsNWidgets(2));

    await tester.ensureVisible(find.text('Belum punya akun? Daftar'));
    await tester.tap(find.text('Belum punya akun? Daftar'));
    await tester.pumpAndSettle();
    expect(find.text('Buat akun'), findsOneWidget);

    await tester.ensureVisible(find.text('Sudah punya akun? Masuk'));
    await tester.tap(find.text('Sudah punya akun? Masuk'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lupa password?'));
    await tester.tap(find.text('Lupa password?'));
    await tester.pumpAndSettle();
    expect(find.text('Kirim tautan reset'), findsOneWidget);
  });
}
