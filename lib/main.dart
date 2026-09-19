import 'package:flutter/material.dart';
import 'screen/home_screen.dart' show KColors, HomeScreen;

void main() {
  runApp(const KPortalApp());
}

class KPortalApp extends StatelessWidget {
  const KPortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'K-Portal',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: KColors.surface,
      ),
      home: const HomeScreen(),
    );
  }
}
