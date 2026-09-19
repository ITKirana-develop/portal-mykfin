import 'package:shared_preferences/shared_preferences.dart';

import 'vpn_config.dart';

/// Data konfigurasi VPN milik satu device -- diisi user sendiri lewat
/// dropdown Pengaturan VPN (bukan hardcode, beda dengan VpnServerConfig
/// yang isinya konfigurasi server dari tim IT).
class VpnConfigData {
  const VpnConfigData({
    required this.privateKey,
    required this.address,
    required this.devicePublicKey,
  });

  final String privateKey;
  final String address;
  final String devicePublicKey;

  /// Dipakai sebagai parameter `serverAddress` di wireguard_flutter_pro.
  /// Server tujuan koneksi sama untuk semua user, jadi diambil dari
  /// VpnServerConfig, bukan dari data per-device.
  String get serverAddress => VpnServerConfig.endpoint;

  /// Format wg-quick config lengkap: bagian device (privateKey,
  /// address) digabung dengan bagian server yang hardcode di
  /// VpnServerConfig -- persis seperti file .conf dari IT.
  String toWgQuickConfig() {
    final buffer = StringBuffer()
      ..writeln('[Interface]')
      ..writeln('PrivateKey = $privateKey')
      ..writeln('Address = $address')
      ..writeln('DNS = ${VpnServerConfig.dns}')
      ..writeln('MTU = ${VpnServerConfig.mtu}')
      ..writeln()
      ..writeln('[Peer]')
      ..writeln('PublicKey = ${VpnServerConfig.publicKeyServer}')
      ..writeln('AllowedIPs = ${VpnServerConfig.allowedIPs}')
      ..writeln('Endpoint = ${VpnServerConfig.endpoint}')
      ..writeln(
        'PersistentKeepalive = ${VpnServerConfig.persistentKeepalive}',
      );
    return buffer.toString();
  }
}

/// Simpan & baca konfigurasi VPN per-device secara lokal di HP.
///
/// TODO: kalau mau lebih aman, Private Key bisa dipindah ke
/// flutter_secure_storage alih-alih SharedPreferences biasa (sama
/// seperti pertimbangan di K-IKAN).
class VpnConfigService {
  VpnConfigService._();
  static final VpnConfigService instance = VpnConfigService._();

  static const _kPrivateKey = 'vpn_private_key';
  static const _kAddress = 'vpn_address';
  static const _kDevicePublicKey = 'vpn_device_public_key';
  static const _kLastActionConnected = 'vpn_last_action_connected';

  Future<VpnConfigData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final privateKey = prefs.getString(_kPrivateKey);
    final address = prefs.getString(_kAddress);
    final devicePublicKey = prefs.getString(_kDevicePublicKey) ?? '';
    if (privateKey == null || privateKey.isEmpty) return null;
    if (address == null || address.isEmpty) return null;
    return VpnConfigData(
      privateKey: privateKey,
      address: address,
      devicePublicKey: devicePublicKey,
    );
  }

  Future<void> save(VpnConfigData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrivateKey, data.privateKey);
    await prefs.setString(_kAddress, data.address);
    await prefs.setString(_kDevicePublicKey, data.devicePublicKey);
  }

  /// Nyimpen aksi TERAKHIR yang user lakuin: true kalau terakhir kali
  /// nyalain VPN, false kalau terakhir kali matiin. Dipakai buat
  /// deteksi mismatch status waktu app dibuka lagi abis di-kill paksa
  /// saat VPN masih nyala -- plugin belum "pegang" balik ke tunnel
  /// yang sebenarnya masih hidup di background. Tanpa ini, user harus
  /// tap ON dulu baru bisa OFF beneran (bug yang sudah diperbaiki di
  /// K-IKAN, di-port ke sini juga).
  Future<bool> getLastActionConnected() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kLastActionConnected) ?? false;
  }

  Future<void> setLastActionConnected(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLastActionConnected, value);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      _kPrivateKey,
      _kAddress,
      _kDevicePublicKey,
      _kLastActionConnected,
    ]) {
      await prefs.remove(key);
    }
  }
}