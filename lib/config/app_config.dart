/// Daftar URL semua aplikasi internal yang bisa diakses lewat K-Portal.
///
/// PENTING: Nilai di bawah ini masih PLACEHOLDER. Ganti dengan URL asli
/// masing-masing aplikasi (didapat dengan klik tiap card di
/// https://portal.mykfin.com/K-Portal/ lewat browser, lalu copy alamat
/// halaman /login yang muncul).
///
/// Kalau nanti ada aplikasi baru yang perlu ditambahkan (atau salah
/// satu pindah alamat), cukup ubah di sini — tidak perlu cari-cari
/// satu-satu di file lain.
class AppConfig {
  AppConfig._();

  /// Website resmi Kirana Food International, dibuka di browser
  /// eksternal (bukan WebView) kalau logo Kirana di header di-tap.
  static const String kiranaWebsiteUrl = 'https://kfifood.com/';

  /// ERP-MyKFIN -- sistem utama/portal utama (card pertama, ditandai
  /// badge "Live"). GANTI dengan URL ERP asli.
  static const String erpMyKfinBaseUrl = 'https://erp.mykfin.com/login';

  static const String kFishBaseUrl = 'https://efile.mykfin.com/login';
  static const String kCrabBaseUrl = 'https://recruitment.mykfin.com/login';
  static const String kWeedBaseUrl = 'https://teknik.mykfin.com/login';
  static const String kSquidBaseUrl = 'https://quality.mykfin.com/';
  static const String kIkanBaseUrl = 'https://office.mykfin.com/login';

  /// Nomor telepon/WhatsApp IT Support -- dipakai tombol "Contact" di
  /// banner Helpdesk. GANTI dengan nomor asli tim IT Kirana.
  static const String itSupportPhone = '+6280000000000';
}
