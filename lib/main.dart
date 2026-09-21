import 'package:flutter/material.dart';
import 'screen/home_screen.dart' show KColors;
import 'screen/splash_screen.dart';

void main() {
  runApp(const KPortalApp());
}

class KPortalApp extends StatelessWidget {
  const KPortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MyKFIN',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: KColors.surface,
      ),
      // Splash tampil dulu 2 detik, baru pindah ke HomeScreen (lihat
      // splash_screen.dart) -- BUKAN langsung ke HomeScreen di sini.
      home: const SplashScreen(),
    );
  }
}