class AppConfig {
  AppConfig._();

  /// Website resmi Kirana Food International, dibuka di browser
  /// eksternal (bukan WebView) kalau logo Kirana di header di-tap.
  static const String kiranaWebsiteUrl = 'https://kfifood.com/';

  /// ERP-MyKFIN -- sistem utama/portal utama (card pertama, ditandai
  /// badge "Live"). GANTI dengan URL ERP asli.
  // static const String erpMyKfinBaseUrl = 'https://erp.mykfin.com/login';

  static const String recruitmentUrl ='https://recruitment.kfifood.com/public/';
  static const String kFishBaseUrl = 'https://efile.mykfin.com/login';
  static const String kCrabBaseUrl = 'https://recruitment.mykfin.com/login';
  static const String kWeedBaseUrl = 'https://teknik.mykfin.com/login';
  static const String kSquidBaseUrl = 'https://quality.mykfin.com/login';
  static const String kIkanBaseUrl = 'https://office.mykfin.com/login';

  /// Nomor telepon/WhatsApp IT Support -- dipakai tombol "Contact" di
  /// banner Helpdesk. GANTI dengan nomor asli tim IT Kirana.
  // static const String itSupportPhone = '+6280000000000';
}
