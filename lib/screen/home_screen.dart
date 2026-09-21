import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_config.dart';
import '../service/vpn_service.dart';
import '../service/vpn_config_service.dart';
import 'webview_screen.dart';

/// Warna-warna dasar tampilan K-Portal.
class KColors {
  KColors._();

  static const Color primary = Color(0xFF30318B);
  static const Color heroNavy = Color(0xFF102A6B);
  static const Color heroSky = Color(0xFF0EA5E9);
  static const Color surface = Color(0xFFF7F8FC);
  static const Color surfaceContainerLowest = Colors.white;
  static const Color surfaceContainerHigh = Color(0xFFEFF1F8);
  static const Color onSurface = Color(0xFF0F172A);
  static const Color onSurfaceVariant = Color(0xFF64748B);
  static const Color outline = Color(0xFF9CA3AF);
  static const Color outlineVariant = Color(0xFFE2E8F0);
  static const Color headerGlowSoft = Color(0x33FFFFFF);
}

/// Satu entri aplikasi yang muncul sebagai card di halaman utama.
class _PortalApp {
  const _PortalApp({
    required this.name,
    required this.description,
    required this.icon,
    required this.baseUrl,
    required this.assetKey,
    this.badge,
    this.badgeColor,
    this.external = false,
  });

  final String name;
  final String description;
  final IconData icon;
  final String baseUrl;
  // Dipakai untuk nama file placeholder gambar (logo per aplikasi):
  // assets/icon/{assetKey}_logo.png
  // Tinggal drop file dengan nama ini nanti, tidak perlu ubah kode lagi.
  final String assetKey;
  final String? badge;
  final Color? badgeColor;
  // Dulu berarti "buka di browser luar". Sekarang SEMUA card dibuka
  // lewat WebView di dalam app -- flag ini cuma menandai bahwa
  // baseUrl sudah URL lengkap (tidak perlu ditambah '/login' saat
  // dibuka), dipakai untuk "Website Utama".
  final bool external;
}

/// Halaman utama K-Portal.
/// Nama class ini SENGAJA "HomeScreen" (bukan PortalHomeScreen), supaya
/// sama seperti struktur project K-IKAN yang jadi acuan — webview_screen.dart
/// memanggil `const HomeScreen()` saat butuh kembali ke halaman utama
/// setelah login ulang, jadi class ini wajib ada persis dengan nama itu.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 6 aplikasi yang bisa diakses. Website Utama sengaja ditaruh paling
  // atas, K-IKAN & yang lain geser ke bawahnya. Kalau nanti akses
  // bertambah, tinggal tambah entri baru di list ini + URL barunya di
  // app_config.dart.
  static final List<_PortalApp> _apps = [
    _PortalApp(
      name: 'Website ',
      description: 'Situs resmi PT. Kirana Food International',
      icon: Icons.language_rounded,
      baseUrl: AppConfig.kiranaWebsiteUrl,
      assetKey: 'website_utama',
      external: true,
    ),
    _PortalApp(
      name: 'K-IKAN',
      description: 'PERMISSION',
      icon: Icons.forum_rounded,
      baseUrl: AppConfig.kIkanBaseUrl,
      assetKey: 'k_ikan',
    ),
    _PortalApp(
      name: 'K-FISH',
      description: 'E-FILE & ARCHIVE',
      icon: Icons.set_meal_rounded,
      baseUrl: AppConfig.kFishBaseUrl,
      assetKey: 'k_fish',
    ),
    _PortalApp(
      name: 'K-CRAB',
      description: 'RECRUITMENT',
      icon: Icons.badge_rounded,
      baseUrl: AppConfig.kCrabBaseUrl,
      assetKey: 'k_crab',
    ),
    _PortalApp(
      name: 'K-WEED',
      description: 'JOB ORDER',
      icon: Icons.warehouse_rounded,
      baseUrl: AppConfig.kWeedBaseUrl,
      assetKey: 'k_weed',
    ),
    _PortalApp(
      name: 'K-SQUID',
      description: 'QUALITY CONTROL',
      icon: Icons.grid_view_rounded,
      baseUrl: AppConfig.kSquidBaseUrl,
      assetKey: 'k_squid',
    ),
  ];

  void _openApp(_PortalApp app) {
    // Semua card sekarang dibuka DI DALAM aplikasi lewat WebView
    // (WebViewScreen), termasuk "Website Utama" -- tidak lagi
    // lompat keluar ke Chrome/browser HP.
    // app.baseUrl untuk Website Utama sudah URL utuh (kfifood.com),
    // jadi tidak perlu ditambah '/login' seperti aplikasi internal.
    final url = app.baseUrl;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WebViewScreen(title: app.name, url: url),
      ),
    );
  }

  void _openRecruitment() {
    final crab = _apps.firstWhere(
      (a) => a.name == 'K-CRAB',
      orElse: () => _apps.first,
    );
    _openApp(crab);
  }

  // Dipanggil saat user narik layar ke bawah (pull-to-refresh).
  // Saat ini cuma refresh tampilan; kalau nanti ada data dari server
  // (mis. status live/badge), tinggal panggil API di sini lalu setState.
  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final apps = _apps;

    return Scaffold(
      backgroundColor: KColors.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: KColors.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: _TopBar(),
              ),
              SliverToBoxAdapter(
                child: _HeroSection(onRecruitmentTap: _openRecruitment),
              ),
              const SliverToBoxAdapter(child: _SectionDivider()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    mainAxisExtent: 168,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final app = apps[index];
                    return _AppCard(app: app, onTap: () => _openApp(app));
                  }, childCount: apps.length),
                ),
              ),
              const SliverToBoxAdapter(child: _Footer()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header atas: tombol "Portal MyKFIN" di kiri, logo Kirana di kanan
/// (bisa di-tap, buka https://kfifood.com/ di browser eksternal).
class _TopBar extends StatefulWidget {
  const _TopBar();

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  VpnConnectionState _state = VpnConnectionState.disconnected;
  bool _busy = false;
  bool _configReady = false;

  bool _vpnMenuOpen = false;
  bool _generating = false;
  bool _saving = false;
  bool _privateKeyVisible = false;

  final _privateKeyController = TextEditingController();
  final _addressController = TextEditingController();
  final _devicePublicKeyController = TextEditingController();

  StreamSubscription<VpnConnectionState>? _vpnSub;

  @override
  void initState() {
    super.initState();
    _initVpn();
    _vpnSub = VpnService.instance.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
    });
  }

  @override
  void dispose() {
    _vpnSub?.cancel();
    _privateKeyController.dispose();
    _addressController.dispose();
    _devicePublicKeyController.dispose();
    super.dispose();
  }

  Future<void> _initVpn() async {
    final connected = await VpnService.instance.isConnectedNow();
    final config = await VpnConfigService.instance.load();
    if (!mounted) return;
    setState(() {
      _state = connected
          ? VpnConnectionState.connected
          : VpnConnectionState.disconnected;
      _configReady = config != null;
      if (config != null) {
        _privateKeyController.text = config.privateKey;
        _addressController.text = config.address;
        _devicePublicKeyController.text = config.devicePublicKey;
      }
    });
  }

  bool get _isOn =>
      _state == VpnConnectionState.connected ||
      _state == VpnConnectionState.connecting;

  void _toggleVpnMenu() {
    setState(() => _vpnMenuOpen = !_vpnMenuOpen);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleVpnConnection(bool turnOn) async {
    if (turnOn && !_configReady) {
      _showSnack('Atur VPN terlebih dahulu (Generate & Simpan) sebelum menyambungkan.');
      if (!_vpnMenuOpen) _toggleVpnMenu();
      return;
    }
    setState(() => _busy = true);
    try {
      if (turnOn) {
        await VpnService.instance.connect();
      } else {
        await VpnService.instance.disconnect();
      }
    } catch (_) {
      _showSnack('VPN gagal ${turnOn ? "tersambung" : "diputuskan"}. Coba lagi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ==== Generate keypair (Private Key + Public Key) untuk device ini ====
  Future<void> _generateKeyPair() async {
    setState(() => _generating = true);
    try {
      final keyPair = await VpnService.instance.generateKeyPair();
      setState(() {
        _privateKeyController.text = keyPair.privateKey;
        _devicePublicKeyController.text = keyPair.publicKey;
      });
    } catch (e) {
      _showSnack('Gagal generate key: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _copyDevicePublicKey() {
    if (_devicePublicKeyController.text.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: _devicePublicKeyController.text));
    _showSnack('Kode berhasil disalin. Kirim ke tim IT untuk didaftarkan.');
  }

  Future<void> _saveVpnSettings() async {
    if (_privateKeyController.text.trim().isEmpty) {
      _showSnack('Ketuk tombol Generate dulu untuk membuat Kode Keamanan Perangkat.');
      return;
    }
    if (_addressController.text.trim().isEmpty) {
      _showSnack('Address wajib diisi.');
      return;
    }
    setState(() => _saving = true);
    try {
      await VpnConfigService.instance.save(
        VpnConfigData(
          privateKey: _privateKeyController.text,
          address: _addressController.text,
          devicePublicKey: _devicePublicKeyController.text,
        ),
      );
      if (!mounted) return;
      setState(() => _configReady = true);
      _showSnack('Pengaturan VPN disimpan.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _statusLabel {
    switch (_state) {
      case VpnConnectionState.connected:
        return 'VPN Aktif';
      case VpnConnectionState.connecting:
        return 'Menyambungkan...';
      case VpnConnectionState.error:
        return 'Terjadi kesalahan';
      case VpnConnectionState.disconnected:
        return 'VPN Tidak Aktif';
    }
  }

  Color get _statusColor {
    switch (_state) {
      case VpnConnectionState.connected:
        return const Color(0xFF34D399);
      case VpnConnectionState.connecting:
        return Colors.orange;
      case VpnConnectionState.error:
        return Colors.red;
      case VpnConnectionState.disconnected:
        return Colors.white.withValues(alpha: 0.6);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.9),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [KColors.primary, Color(0xFF4338CA)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: _statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Portal MyKFIN',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Ikon setting VPN. Tap = buka/tutup dropdown di
                    // bawah (status On/Off + Pengaturan), TIDAK
                    // pindah ke halaman baru.
                    InkWell(
                      onTap: _toggleVpnMenu,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          _vpnMenuOpen
                              ? Icons.close_rounded
                              : Icons.settings_rounded,
                          size: 20,
                          color: const Color.fromARGB(255, 0, 0, 0),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Image.asset(
                    'assets/icon/kirana_logo.png',
                    height: 26,
                    errorBuilder: (context, error, stackTrace) {
                      return const Text(
                        'KIRANA',
                        style: TextStyle(
                          color: Color(0xFFEE2737),
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Dropdown VPN: muncul di bawah top bar begitu ikon setting
          // di-tap. Isinya status/toggle On-Off + form Pengaturan
          // (Generate key, eye icon show/hide, Public Key + copy,
          // Address) -- semua langsung di sini, bukan halaman baru.
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _vpnMenuOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: KColors.outlineVariant),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Status + On/Off VPN ---
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _statusLabel,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: KColors.onSurface,
                          ),
                        ),
                      ),
                      _busy || _state == VpnConnectionState.connecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            )
                          : Switch(
                              value: _isOn,
                              activeThumbColor: KColors.primary,
                              onChanged: _busy
                                  ? null
                                  : (v) => _toggleVpnConnection(v),
                            ),
                    ],
                  ),
                  if (!_configReady) ...[
                    const SizedBox(height: 6),
                    Text(
                      'VPN belum diatur. Isi Pengaturan di bawah dulu.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: KColors.outlineVariant),
                  const SizedBox(height: 12),

                  // --- Settings VPN ---
                  const Text(
                    'Pengaturan VPN',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: KColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Private Key: read-only, HARUS hasil generate di
                  // device ini (bukan diketik manual) -- ada tombol
                  // mata (show/hide) + tombol refresh (generate).
                  TextField(
                    controller: _privateKeyController,
                    readOnly: true,
                    obscureText: !_privateKeyVisible,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Kode Keamanan Perangkat (Private Key)',
                      labelStyle: const TextStyle(fontSize: 10.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _privateKeyVisible
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 18,
                            ),
                            tooltip: _privateKeyVisible
                                ? 'Sembunyikan Kode'
                                : 'Tampilkan Kode',
                            onPressed: () => setState(
                              () => _privateKeyVisible = !_privateKeyVisible,
                            ),
                          ),
                          _generating
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                  ),
                                  tooltip: 'Buat kode baru untuk perangkat ini',
                                  onPressed: _generateKeyPair,
                                ),
                        ],
                      ),
                    ),
                  ),

                  if (_devicePublicKeyController.text.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Public Key',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: KColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _devicePublicKeyController,
                      readOnly: true,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Kode Publik Perangkat',
                        labelStyle: const TextStyle(fontSize: 10.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          tooltip: 'Salin Kode',
                          onPressed: _copyDevicePublicKey,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                  TextField(
                    controller: _addressController,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Address (contoh: 10.8.0.5/32)',
                      labelStyle: const TextStyle(fontSize: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ketuk Refresh pada Private Key yang hanya untuk perangkat ini, lalu salin Public Key dan kirim ke tim IT.',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: KColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _saveVpnSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: KColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Simpan',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hero section: gradient navy -> sky, ilustrasi kecil, headline, dan
/// tombol pill "Recruitment Information".
class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.onRecruitmentTap});

  final VoidCallback onRecruitmentTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(32),
        bottomRight: Radius.circular(32),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [KColors.heroNavy, Color(0xFF1E40AF), KColors.heroSky],
          ),
        ),
        child: Column(
          children: [
            // Placeholder ilustrasi hero. Tinggal taruh file di
            // assets/icon/hero_illustration.png (folder assets/icon/
            // sudah terdaftar di pubspec.yaml, tidak perlu diedit lagi).
            // Selama file belum ada, tampil ilustrasi vector bawaan
            // sebagai pengganti sementara.
            Image.asset(
              'assets/icon/hero_illustration.png',
              height: 130,
              errorBuilder: (context, error, stackTrace) =>
                  const _HeroIllustration(),
            ),
            const SizedBox(height: 18),
            const Text(
              'Quick Access to All',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const Text(
              'Our Internal Applications',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF7DD3FC),
                fontSize: 21,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: onRecruitmentTap,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Recruitment Information',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ilustrasi kecil ala "laptop mockup" dengan ikon-ikon melayang di
/// sekitarnya, mereplikasi bagian hero di versi web.
class _HeroIllustration extends StatelessWidget {
  const _HeroIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Alas laptop
          Positioned(
            bottom: 4,
            child: Container(
              width: 168,
              height: 12,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [Colors.white70, Colors.white, Colors.white70],
                ),
              ),
            ),
          ),
          // Layar laptop
          Positioned(
            bottom: 14,
            child: Container(
              width: 132,
              height: 100,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: KColors.heroSky.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0284C7), Color(0xFF4338CA)],
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 5,
                    width: 60,
                    decoration: BoxDecoration(
                      color: KColors.heroSky.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Ikon melayang: cloud
          const Positioned(
            top: 0,
            left: 4,
            child: _FloatingChip(icon: Icons.cloud_rounded),
          ),
          // Ikon melayang: wifi
          const Positioned(
            top: 6,
            right: 0,
            child: _FloatingChip(icon: Icons.wifi_rounded),
          ),
          // Ikon melayang: shield
          const Positioned(
            bottom: 2,
            left: 0,
            child: _FloatingChip(icon: Icons.verified_user_rounded),
          ),
        ],
      ),
    );
  }
}

class _FloatingChip extends StatelessWidget {
  const _FloatingChip({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.9)),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 3.5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                colors: [KColors.heroNavy, KColors.heroSky],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Choose the application you need from the links below',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w700,
              color: KColors.heroNavy,
            ),
          ),
        ],
      ),
    );
  }
}

/// Card aplikasi: banner gradient di atas + badge ikon bulat overlap +
/// badge status opsional (mis. "LIVE") + judul, deskripsi, "Launch App".
class _AppCard extends StatelessWidget {
  const _AppCard({required this.app, required this.onTap});

  final _PortalApp app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KColors.primary, // #30318B, sama rata semua kartu
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shadowColor: KColors.primary.withValues(alpha: 0.35),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Stack(
            children: [
              if (app.badge != null)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: app.badgeColor ?? Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      app.badge!,
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/icon/${app.assetKey}_logo.png',
                      width: 80,
                      height: 80,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          Icon(app.icon, size: 56, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      app.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // TODO: isi keterangan singkat menu ini sendiri di sini,
                    // contoh: "Akses info & pengumuman internal".
                    // Placeholder-nya sudah disiapkan, tinggal ganti teksnya
                    // (atau ganti app.description di list _apps di atas).
                    Text(
                      app.description,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.75),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [KColors.heroNavy, Color(0xFF1E3A8A)]),
      ),
      child: const Column(
        children: [
          Text(
            'Portal MyKFIN - PT. Kirana Food International',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFFDBEAFE),
            ),
          ),
         
        ],
      ),
    );
  }
}