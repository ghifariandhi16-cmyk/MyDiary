import 'package:flutter/material.dart';

import 'controllers/auth_controller.dart';
import 'theme/app_colors.dart';
import 'views/auth_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyDiaryApp());
}

class MyDiaryApp extends StatelessWidget {
  final AuthController? authController;

  const MyDiaryApp({super.key, this.authController});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'My Diary',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF7FAF9),
      colorScheme: ColorScheme.fromSeed(seedColor: teal),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7FAF9),
        foregroundColor: ink,
        elevation: 0,
      ),
    ),
    home: AuthGate(authController: authController),
  );
}
