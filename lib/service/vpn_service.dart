import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wireguard_flutter_pro/wireguard_flutter_pro.dart';


import 'vpn_config_service.dart';

/// Status koneksi VPN WireGuard.
enum VpnConnectionState { connected, connecting, disconnected, error }

/// Pasangan key hasil generate di device ini.
class VpnKeyPair {
  const VpnKeyPair({required this.privateKey, required this.publicKey});

  final String privateKey;
  final String publicKey;
}

/// Wrapper singleton di atas package `wireguard_flutter_pro` -- port
/// persis dari implementasi yang sudah terbukti jalan di project
/// kira_patrol_flutter (K-IKAN), termasuk fix auto-sync status supaya
/// tombol "Putuskan" tidak perlu ditekan berkali-kali (nyala dulu baru
/// bisa mati) setelah app sempat di-kill paksa saat VPN masih aktif.
class VpnService {
  VpnService._();
  static final VpnService instance = VpnService._();

  static const _interfaceName = 'kportal_wg0';
  static const _providerBundleIdentifier =
      'com.kirana.portalmykfin.WireGuardExtension'; // sesuaikan dgn iOS bundle id

  final _wireguard = WireGuardFlutter.instance;

  bool _initialized = false;
  StreamSubscription<VpnStage>? _nativeSub;

  final _stateController = StreamController<VpnConnectionState>.broadcast();

  /// Stream status VPN yang sudah disederhanakan, dipakai UI lewat
  /// `VpnService.instance.stateStream.listen(...)`.
  Stream<VpnConnectionState> get stateStream => _stateController.stream;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _wireguard.initialize(interfaceName: _interfaceName);
    _nativeSub = _wireguard.vpnStageSnapshot.listen((stage) {
      _stateController.add(_mapStage(stage));
    });
    _initialized = true;
  }

  VpnConnectionState _mapStage(VpnStage stage) {
    switch (stage) {
      case VpnStage.connected:
        return VpnConnectionState.connected;
      case VpnStage.connecting:
      case VpnStage.preparing:
      case VpnStage.authenticating:
      case VpnStage.waitingConnection:
      case VpnStage.reconnect:
        return VpnConnectionState.connecting;
      case VpnStage.disconnecting:
      case VpnStage.disconnected:
      case VpnStage.noConnection:
      case VpnStage.exiting:
        return VpnConnectionState.disconnected;
      case VpnStage.denied:
        return VpnConnectionState.error;
    }
  }

  /// Cek status VPN sekarang juga (dipanggil sekali waktu dropdown
  /// Pengaturan VPN dibuka), tanpa perlu nunggu event dari stream.
  ///
  /// PENTING: kalau plugin bilang "terputus" TAPI terakhir kali user
  /// memang menyalakan VPN, besar kemungkinan tunnel-nya sebenarnya
  /// MASIH hidup di background (app sempat di-kill paksa saat VPN
  /// aktif) -- plugin baru saja dibuat ulang dan belum "pegang" balik
  /// ke tunnel itu. Di sini kita sinkronkan OTOMATIS di belakang
  /// layar, supaya toggle langsung menunjukkan status yang BENAR, dan
  /// tombol "Putuskan" langsung berhasil di percobaan pertama.
    Future<bool> isConnectedNow() async {
    await _ensureInitialized();
    final stage = await _wireguard.stage();
    var connected = stage == VpnStage.connected;
    debugPrint('VPN DEBUG: stage awal=$stage, connected=$connected');

    if (!connected) {
      final lastActionConnected = await VpnConfigService.instance
          .getLastActionConnected();
      debugPrint('VPN DEBUG: lastActionConnected=$lastActionConnected');
      if (lastActionConnected) {
        final config = await VpnConfigService.instance.load();
        if (config != null) {
                    try {
            debugPrint('VPN DEBUG: mencoba auto-reconnect...');
            await _wireguard.startVpn(
              serverAddress: config.serverAddress,
              wgQuickConfig: config.toWgQuickConfig(),
              providerBundleIdentifier: _providerBundleIdentifier,
            );
            await Future.delayed(const Duration(milliseconds: 800));
            final restage = await _wireguard.stage();
            connected = restage == VpnStage.connected;
            debugPrint('VPN DEBUG: hasil auto-reconnect, restage=$restage, connected=$connected');
          } catch (e) {
            debugPrint('VPN DEBUG: auto-reconnect GAGAL -> $e');
            connected = false;
          }
        }
      }
    }

    if (connected) {
      _stateController.add(VpnConnectionState.connected);
    }

    return connected;
  }

  /// Sambungkan VPN pakai config yang tersimpan di VpnConfigService
  /// (Private Key + Address per-device, digabung dengan
  /// VpnServerConfig yang hardcode).
  Future<void> connect() async {
    final config = await VpnConfigService.instance.load();
    if (config == null) {
      throw StateError(
        'Konfigurasi VPN belum diisi. Buka Pengaturan VPN dulu.',
      );
    }

    await _ensureInitialized();
    _stateController.add(VpnConnectionState.connecting);
    try {
      await _wireguard.startVpn(
        serverAddress: config.serverAddress,
        wgQuickConfig: config.toWgQuickConfig(),
        providerBundleIdentifier: _providerBundleIdentifier,
      );
      await VpnConfigService.instance.setLastActionConnected(true);
    } catch (e) {
      _stateController.add(VpnConnectionState.error);
      rethrow;
    }
  }

  /// Putuskan VPN. Kalau plugin tidak punya pegangan ke tunnel yang
  /// sebenarnya masih hidup, sambungkan ulang dulu untuk "mengambil
  /// alih" tunnel lama itu -- Android/iOS cuma izinkan 1 VPN aktif
  /// se-sistem -- baru langsung diputuskan lagi dengan pegangan yang
  /// sekarang valid. User cukup tekan "Putuskan" SEKALI.
  Future<void> disconnect() async {
    await _ensureInitialized();

    try {
      await _wireguard.stopVpn();
      await VpnConfigService.instance.setLastActionConnected(false);
      _stateController.add(VpnConnectionState.disconnected);
      return;
    } on PlatformException catch (e) {
      final isTunnelNotRunning = (e.message ?? '').toLowerCase().contains(
        'tunnel is not running',
      );
      if (!isTunnelNotRunning) rethrow;
    }

    final config = await VpnConfigService.instance.load();
    if (config != null) {
      try {
        await _wireguard.startVpn(
          serverAddress: config.serverAddress,
          wgQuickConfig: config.toWgQuickConfig(),
          providerBundleIdentifier: _providerBundleIdentifier,
        );
        await Future.delayed(const Duration(milliseconds: 1200));
        await _wireguard.stopVpn();
        await VpnConfigService.instance.setLastActionConnected(false);
        _stateController.add(VpnConnectionState.disconnected);
        return;
      } catch (_) {
        // lanjut ke penanganan gagal di bawah
      }
    }

    // Benar-benar tidak berhasil diputuskan dari app. JANGAN bohongi
    // status jadi "terputus" -- tetap tampilkan sebagai tersambung,
    // dan kasih tahu user cara matikan manual.
    _stateController.add(VpnConnectionState.connected);
    throw StateError(
      'VPN tidak bisa diputuskan otomatis. Matikan manual lewat '
      'Settings > Network > VPN di HP.',
    );
  }

  /// Generate Private Key + Public Key baru untuk device ini lewat
  /// fungsi native package wireguard_flutter_pro -- private key tidak
  /// pernah keluar dari HP, cuma public key yang perlu dikirim ke tim
  /// IT untuk didaftarkan sebagai peer.
  Future<VpnKeyPair> generateKeyPair() async {
    await _ensureInitialized();
    final pair = await _wireguard.generateKeyPair();
    return VpnKeyPair(privateKey: pair.privateKey, publicKey: pair.publicKey);
  }

  void dispose() {
    _nativeSub?.cancel();
    _stateController.close();
  }
}