/// Konfigurasi server VPN WireGuard untuk MyKFIN.
///
/// SAMA dengan server yang dipakai K-IKAN (kira_patrol_flutter) --
/// satu VPN untuk semua akses (ERP, K-Fish, K-Crab, K-IKAN, dst).
/// Nilai-nilai di bawah ini SENGAJA hardcode karena ini konfigurasi
/// server dari tim IT, bukan sesuatu yang diisi user. Yang beda per
/// user/HP cuma Private Key & Address (2 field itu diisi lewat
/// dropdown Pengaturan VPN).
///
/// Kalau suatu saat server pindah / key di-rotate, cukup ganti nilai
/// di sini -- tidak perlu ubah file lain.
class VpnServerConfig {
  VpnServerConfig._();

  /// Public Key milik server WireGuard (bukan punya user).
  static const String publicKeyServer =
      'WybQohqBIBM8dNhI1ry2w0ImjlyktT1diPeHwsJ/1k4=';

  /// Alamat server VPN, format host:port.
  static const String endpoint = '36.92.192.109:51820';

  static const String dns = '129.168.1.1';

  /// Rentang IP yang dilewatkan lewat VPN.
  static const String allowedIPs = '129.168.0.0/16, 10.6.0.0/24';

  static const int persistentKeepalive = 25;

  static const int mtu = 1280;
}