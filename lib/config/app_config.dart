class AppConfig {
  AppConfig._();
 
  /// Website resmi Kirana Food International, dibuka di browser
  /// eksternal (bukan WebView) kalau logo Kirana di header di-tap.
  static const String kiranaWebsiteUrl = 'https://kfifood.com/';
 
  /// ERP-MyKFIN -- card ERP di halaman utama (dibuka di browser eksternal).
  static const String erpBaseUrl = 'https://erp.mykfin.com/login';

  static const String recruitmentUrl ='https://recruitment.kfifood.com/public/';
  static const String kFishBaseUrl = 'https://efile.mykfin.com';
  static const String kCrabBaseUrl = 'https://recruitment.mykfin.com';
  static const String kWeedBaseUrl = 'https://teknik.mykfin.com';
  static const String kSquidBaseUrl = 'https://quality.mykfin.com';
  static const String kIkanBaseUrl = 'https://office.mykfin.com';
 
  /// Nomor telepon/WhatsApp IT Support -- dipakai tombol "Contact" di
  /// banner Helpdesk. GANTI dengan nomor asli tim IT Kirana.
  // static const String itSupportPhone = '+6280000000000';
}