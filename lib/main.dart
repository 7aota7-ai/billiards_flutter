import 'package:flutter/material.dart';

import 'screens/setup_screen.dart';
import 'theme/apple_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BilliardsApp());
}

class BilliardsApp extends StatelessWidget {
  const BilliardsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ビリヤードスコア',
      debugShowCheckedModeBanner: false,
      theme: buildAppleTheme(),
      home: const SetupScreen(),
    );
  }
}
