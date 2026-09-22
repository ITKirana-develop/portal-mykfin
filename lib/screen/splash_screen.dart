import 'dart:ui';

import 'package:flutter/material.dart';
import 'home_screen.dart';

/// Halaman pembuka (splash) yang muncul sebentar sebelum masuk ke
/// HomeScreen. Ditambahkan karena Portal MyKFIN bisa dibuka dari
/// jaringan mana pun (bukan cuma WiFi kantor), jadi butuh jeda
/// singkat di awal sebelum user melihat daftar menu.
///
/// PENTING: arahkan `home:` di main.dart ke `const SplashScreen()`
/// (bukan lagi langsung ke HomeScreen) supaya splash ini yang
/// pertama muncul.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _loaderFade;

  // Total waktu splash ditampilkan sebelum pindah ke HomeScreen.
  // Sengaja lebih lama dari durasi animasi supaya ada jeda "diam"
  // sebentar setelah animasi selesai, tidak langsung lompat.
  static const _totalHold = Duration(milliseconds: 2400);

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );

    // Logo: muncul dengan efek scale "memantul" (elasticOut).
    _logoScale = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.65, curve: Curves.elasticOut),
    );
    _logoFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );

    // Loading indicator: muncul paling terakhir.
    _loaderFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.75, 1.0, curve: Curves.easeOut),
    );

    _ctrl.forward();
    _goToHome();
  }

  Future<void> _goToHome() async {
    // Kalau nanti splash ini juga dipakai untuk proses lain (mis. cek
    // versi app, cek sesi login), taruh proses itu di sini sebelum
    // Navigator.pushReplacement dipanggil.
    await Future.delayed(_totalHold);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
    Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 106, 125, 185),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background gradient dasar — sama seperti hero section di
          // Home Screen (navy di atas, sky blue cerah di bawah), biar
          // konsisten dan senada dengan biru di logo & Portal Web.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.fromARGB(255, 71, 154, 255),
                  Color.fromARGB(255, 171, 216, 241),
                  Color.fromARGB(255, 15, 12, 231),
                ],
              ),
            ),
          ),
          // Aksen blob cahaya samar, supaya background gak flat.
          Positioned(
            top: -80,
            right: -60,
            child: _GlowBlob(size: 220, opacity: 0.10),
          ),
          Positioned(
            bottom: -100,
            left: -70,
            child: _GlowBlob(size: 260, opacity: 0.08),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _logoScale,
                  child: FadeTransition(
                    opacity: _logoFade,
                    child: const _SplashLogo(size: 180),
                  ),
                ),
                const SizedBox(height: 36),
                FadeTransition(
                  opacity: _loaderFade,
                  child: const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo splash. File logo di assets/icon/ pernah beberapa kali
/// ke-rename (mis. saat setup flutter_launcher_icons), jadi widget ini
/// coba beberapa kemungkinan nama file secara berurutan -- kalau nama
/// pertama gak ketemu, otomatis coba nama berikutnya -- baru kalau
/// semua gak ada, jatuh ke teks "MyKFIN" putih sebagai pengganti
/// sementara.
///
/// TAMBAHKAN nama file baru di depan list ini kalau logo di-rename
/// lagi nanti, supaya splash gak balik nampilin teks putih doang.
class _SplashLogo extends StatelessWidget {
  const _SplashLogo({required this.size});

  final double size;

  static const _candidates = [
    'assets/icon/mykfin_logo.png',
    'assets/icon/mykfin_icon_foreground.png',
    'assets/icon/logo_foreground.png',
    'assets/icon/logo.png',
  ];

  @override
  Widget build(BuildContext context) {
    return _tryLoad(0);
  }

  Widget _tryLoad(int index) {
    if (index >= _candidates.length) {
      return SizedBox(
        width: size,
        child: const Text(
          'MyKFIN',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 28,
            letterSpacing: 0.3,
          ),
        ),
      );
    }
    return Image.asset(
      _candidates[index],
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => _tryLoad(index + 1),
    );
  }
}
class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: opacity),
        ),
      ),
    );
  }
}