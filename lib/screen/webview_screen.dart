import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'home_screen.dart';

/// Pilihan di menu (tombol melayang) pada WebViewScreen.
enum _WebMenuAction { back, portal, quit }

class WebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  /// Kalau diisi, begitu WebView berhasil navigasi ke URL yang mengandung
  /// teks ini (misal setelah redirect sukses submit form), screen ini
  /// otomatis ditutup (pop) balik ke screen sebelumnya. Opsional — kalau
  /// null, behavior lama (biarkan WebView terbuka terus) tidak berubah.
  final String? closeOnUrlContains;

  /// Kalau diisi, begitu WebView selesai load URL yang membuat fungsi ini
  /// return true (mis. url.contains('/dashboard')), seluruh stack
  /// navigasi dibersihkan dan pindah ke HomeScreen Flutter — sama seperti
  /// logic di main.dart abis login pertama kali. Dipakai misalnya setelah
  /// user logout lalu login ulang lewat WebView ini (bukan lewat WebView
  /// awal di main.dart), supaya tidak nyangkut nampilin dashboard Laravel
  /// mentah di dalam WebView.
  final bool Function(String url)? redirectHomeWhen;

  /// Kalau false, AppBar (termasuk judulnya) tidak ditampilkan sama sekali
  /// — WebView mengisi penuh layar, persis seperti tampilan login pertama
  /// kali di main.dart. Default true (tampilkan AppBar seperti biasa),
  /// supaya semua pemanggilan WebViewScreen yang sudah ada di modul-modul
  /// lain tidak berubah.
  final bool showAppBar;

  /// Kalau false, WebView TIDAK menempelkan '?mobile_app=1' ke URL
  /// yang dibuka. Default true (perilaku lama, dibutuhkan aplikasi
  /// internal Kirana). Diset false untuk situs LUAR (mis. website
  /// resmi Kirana) -- soalnya parameter tambahan itu bisa bikin CDN
  /// situs luar selalu miss cache (selalu ambil versi baru dari
  /// server, bukan versi cepat yang sudah di-cache), yang bikin
  /// loading kerasa lebih lambat dari seharusnya.
  final bool addMobileAppParam;

  const WebViewScreen({
    super.key,
    required this.url,
    required this.title,
    this.closeOnUrlContains,
    this.redirectHomeWhen,
    this.showAppBar = true,
    this.addMobileAppParam = false,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController controller;
  bool isLoading = true;
  int loadingProgress = 0;
  bool hasError = false;

  // Overlay loading di-hide begitu progress halaman nyampe ambang ini
  // -- TIDAK nunggu onPageFinished (100%). onPageFinished baru nembak
  // setelah SEMUA resource kelar (gambar, font, script analytics/chat
  // widget, dll), padahal konten utama halaman biasanya udah kebentuk
  // & bisa dipakai jauh sebelum itu. Nunggu 100% bikin overlay
  // nyangkut lama padahal user udah bisa mulai berinteraksi.
  // Threshold 55% dipilih supaya masih aman (bukan pas baru mulai
  // loading dan halaman masih kosong-blank), sambil tetap kerasa jauh
  // lebih cepat dibanding nunggu 100%.
  static const int _loadingHideThreshold = 55;

  // ==== State untuk pull-to-refresh (geser dari atas) ====
  // WebView bukan widget scroll biasa di Flutter (dia native view
  // terpisah), jadi RefreshIndicator bawaan Flutter tidak otomatis
  // bisa mendeteksi swipe di dalamnya. _webViewAtTop dipakai supaya
  // gesture geser cuma dianggap "mau refresh" kalau halaman web-nya
  // memang sedang di posisi paling atas (bukan pas user lagi scroll
  // biasa di tengah halaman) -- nilainya diupdate lewat JavaScript
  // channel _ScrollTracker di bawah.
  bool _webViewAtTop = true;
  double _pullDistance = 0;
  bool _refreshing = false;

  static const double _pullTriggerThreshold = 72;
  static const double _pullMaxDistance = 110;

  // ==== State untuk tombol back melayang (draggable) ====
  // Ditambahkan karena banyak user bingung cari tombol back saat
  // AppBar disembunyikan (showAppBar: false) -- tombol ini selalu
  // muncul di atas WebView apa pun kondisi showAppBar, bisa digeser
  // bebas, dan posisinya di-clamp supaya tidak pernah nyangkut/hilang
  // di luar layar (misal abis rotate atau ganti ukuran window).
  static const double _floatingBackButtonSize = 44;
  Offset? _floatingBackButtonPosition;

  @override
  void initState() {
    super.initState();

    // Minta izin kamera & lokasi Android SEBELUM WebView dibuka,
    // supaya saat halaman Laravel minta akses kamera (scan QR) atau
    // lokasi (cek checkpoint), sistem Android sudah mengizinkan.
    _requestCameraPermission();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // WAJIB di-set: tanpa ini, WebView Android bisa nampilin layar
      // HITAM sesaat (bahkan kadang lama/nyangkut) sebelum konten
      // halaman selesai di-render, terutama di situs yang berat kayak
      // kfifood.com. Warna putih dipilih supaya nyambung mulus ke
      // splash/loading indicator putih yang sudah ada.
      ..setBackgroundColor(Colors.white)
      // Channel buat lacak posisi scroll halaman web, dipakai supaya
      // gesture pull-to-refresh cuma aktif kalau halaman sedang di
      // paling atas. Halaman web tidak perlu diubah kodenya -- script
      // pelacaknya di-inject otomatis lewat onPageStarted di bawah.
      ..addJavaScriptChannel(
        'FlutterScrollTracker',
        onMessageReceived: (message) {
          if (!mounted) return;
          final atTop = message.message == 'top';
          if (atTop != _webViewAtTop) {
            setState(() => _webViewAtTop = atTop);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              isLoading = true;
              hasError = false;
              loadingProgress = 0;
              _webViewAtTop = true;
            });
          },

          onProgress: (progress) {
            if (mounted) {
              setState(() {
                loadingProgress = progress;
                // Begitu progress udah lewat threshold, langsung
                // anggap "selesai loading" dari sisi tampilan --
                // overlay ke-fade duluan sementara sisa resource
                // (gambar/script non-kritis) tetap lanjut load di
                // belakang layar tanpa menahan user nunggu.
                if (progress >= _loadingHideThreshold) {
                  isLoading = false;
                }
              });
            }
          },

          onPageFinished: (url) {
            setState(() {
              isLoading = false;
            });

            // Pasang listener scroll di halaman web, laporkan tiap
            // kali posisi scroll berubah lewat FlutterScrollTracker.
            // window.__ktFlutterScrollBound dipakai supaya listener
            // tidak dobel-terpasang kalau onPageFinished sempat
            // terpanggil lebih dari sekali untuk halaman yang sama.
            controller.runJavaScript('''
              if (!window.__ktFlutterScrollBound) {
                window.__ktFlutterScrollBound = true;
                // Di-throttle pakai requestAnimationFrame: event 'scroll'
                // bisa nembak puluhan kali per detik saat scroll cepat,
                // dan tiap panggilan postMessage() nyeberang JS<->Native
                // bridge -- kalau tidak di-throttle, ini ikut membebani
                // main thread pas lagi scroll dan bikin scroll kerasa
                // berat/ngelag dibanding browser biasa.
                var __ktTicking = false;
                var __ktLastAtTop = null;
                var reportScroll = function() {
                  __ktTicking = false;
                  var atTop = (window.scrollY || document.documentElement.scrollTop || 0) <= 0;
                  if (atTop !== __ktLastAtTop) {
                    __ktLastAtTop = atTop;
                    FlutterScrollTracker.postMessage(atTop ? 'top' : 'nottop');
                  }
                };
                window.addEventListener('scroll', function() {
                  if (!__ktTicking) {
                    __ktTicking = true;
                    window.requestAnimationFrame(reportScroll);
                  }
                }, { passive: true });
                reportScroll();
              }
            ''');

            // Auto-close: dipakai misalnya oleh Lapor Darurat, supaya
            // begitu Laravel redirect balik ke Menu Ramah HP setelah
            // submit sukses, langsung balik ke Menu Kira Patrol Flutter
            // (bukan nampilin halaman Laravel itu di dalam WebView).
            if (widget.closeOnUrlContains != null &&
                url.contains(widget.closeOnUrlContains!)) {
              if (mounted) {
                Navigator.of(context).pop(true);
              }
            }

            // Login ulang berhasil (mis. abis logout) -> bersihkan stack,
            // pindah ke HomeScreen Flutter, jangan tampilkan dashboard
            // Laravel mentah di dalam WebView ini.
            if (widget.redirectHomeWhen != null &&
                widget.redirectHomeWhen!(url)) {
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const HomeScreen(),
                  ),
                  (route) => false,
                );
              }
            }
          },

          // Jaring pengaman kedua: kalau Laravel balas 403 (menu:xxx
          // middleware nolak karena user sebenarnya tidak punya akses —
          // mis. hak akses baru saja diubah Superadmin sementara app
          // masih terbuka, atau ada card yang kelewat belum difilter di
          // sisi Flutter), JANGAN biarkan halaman error mentah Laravel
          // ("403 ANDA TIDAK MEMILIKI AKSES...") nampil dan bikin user
          // nyangkut. Langsung kasih tahu & otomatis balik.
          onHttpError: (HttpResponseError error) {
            final statusCode = error.response?.statusCode;
            if (statusCode == 403 && mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Kamu tidak punya akses ke halaman ini.'),
                  duration: Duration(seconds: 3),
                ),
              );
            }
          },

          // Halaman error jaringan bawaan WebView (mis. "ERR_INTERNET_
          // DISCONNECTED", "ERR_CONNECTION_REFUSED", timeout) tampilannya
          // polos dan bikin bingung. Tangkap di sini kalau errornya untuk
          // frame utama (bukan sekadar sub-resource seperti font/icon yang
          // gagal load), lalu tampilkan halaman error kita sendiri.
          onWebResourceError: (error) {
            final isMainFrame = error.isForMainFrame ?? true;
            if (isMainFrame && mounted) {
              setState(() {
                hasError = true;
                isLoading = false;
              });
            }
          },

          onNavigationRequest: (request) {
            final uri = Uri.parse(request.url);

            // Tangkap link download QR code (route qrcode, BUKAN qrcode.preview)
            // supaya file benar-benar didownload ke HP, bukan dibuka di WebView.
            if (_isDownloadUrl(uri)) {
              _downloadFile(request.url);
              return NavigationDecision.prevent;
            }

            // JANGAN di-intercept/rewrite: /login dan /mobile-logout.
            // Alasan: navigasi ke sini seringkali hasil REDIRECT dari
            // server (misal setelah Auth::logout() -> redirect('/login')).
            // Kalau di-intercept lalu dibikin request baru lewat
            // controller.loadRequest(), cookie session yang baru saja
            // di-regenerate oleh Laravel bisa belum konsisten kepakai di
            // request kedua itu, jadi /login malah kebaca masih "login"
            // (session lama) dan dilempar balik ke Dashboard oleh
            // middleware guest. Biarkan redirect asli diikuti apa adanya.
            final isAuthPage =
                uri.path == '/login' || uri.path.contains('/mobile-logout');
            if (isAuthPage) {
              return NavigationDecision.navigate;
            }

            // Otomatis tambahkan mobile_app=1
            // ke halaman Laravel yang belum memilikinya.
            if (uri.host == Uri.parse(widget.url).host) {
              if (uri.queryParameters['mobile_app'] != '1') {
                final newUri = uri.replace(
                  queryParameters: {
                    ...uri.queryParameters,
                    'mobile_app': '1',
                  },
                );

                controller.loadRequest(newUri);

                return NavigationDecision.prevent;
              }
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(
        widget.addMobileAppParam
            ? _addMobileAppParameter(Uri.parse(widget.url))
            : Uri.parse(widget.url),
      );

    // Handler khusus Android: setujui otomatis permintaan kamera/mic
    // dari halaman web (dipakai fitur Scan QR di Form Patroli).
    final platformController = controller.platform;
    if (platformController is AndroidWebViewController) {
      platformController.setOnPlatformPermissionRequest(
        (request) {
          request.grant();
        },
      );

      // Handler khusus Android: buka picker foto (Ambil Foto / Galeri)
      // saat halaman web menyentuh <input type="file"> (dipakai field
      // "Foto Bukti" di Form Patroli & Lapor Darurat).
      platformController.setOnShowFileSelector(_handleFileSelector);

      // Handler khusus Android: setujui otomatis permintaan lokasi (GPS)
      // dari halaman web (dipakai fitur cek lokasi checkpoint di Form
      // Patroli). Ini API terpisah dari setOnPlatformPermissionRequest
      // di atas (yang hanya menangani kamera/mic) — tanpa handler ini,
      // WebView Android akan SELALU menolak request geolocation dari
      // JavaScript walaupun izin lokasi di Settings Android sudah Allow.
      platformController.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt:(GeolocationPermissionsRequestParams request) async {
          return const GeolocationPermissionsResponse(
            allow: true,
            retain: true,
          );
        },
      );
    }
  }

  Future<List<String>> _handleFileSelector(
    FileSelectorParams params,
  ) async {
    final source = await _pickImageSource();
    if (source == null) return [];

    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: source,
      imageQuality: 80,
    );

    if (file == null) return [];

    return [Uri.file(file.path).toString()];
  }

  Future<ImageSource?> _pickImageSource() async {
    if (!mounted) return null;

    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: const Text('Ambil Foto'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Pilih dari Galeri'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _requestCameraPermission() async {
    if (Platform.isAndroid) {
      await Permission.camera.request();
      await Permission.location.request();
    }
  }

  Uri _addMobileAppParameter(Uri uri) {
    if (uri.queryParameters['mobile_app'] == '1') {
      return uri;
    }

    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'mobile_app': '1',
      },
    );
  }

  // =========================================================
  // DOWNLOAD FILE (khusus link download, misal QR code)
  // =========================================================

  // Sesuaikan pattern ini dengan route Laravel-mu.
  // Route qrcode.preview (untuk tampil di <img>) TIDAK boleh ketangkap,
  // hanya route qrcode (tombol Download) yang ketangkap.
  bool _isDownloadUrl(Uri uri) {
    final path = uri.path;

    // QR code checkpoint (route qrcode, BUKAN qrcode.preview).
    final isQrDownload = path.contains('/qrcode') && !path.contains('/preview');

    // Export Excel Riwayat Patroli (route patrol/export).
    final isExportDownload = path.contains('/patrol/export');

    return isQrDownload || isExportDownload;
  }

  Future<void> _downloadFile(String url) async {
    try {
      if (Platform.isAndroid) {
        // Android 13+ tidak butuh permission ini untuk simpan ke Download,
        // tapi request tetap aman untuk versi Android lama.
        await Permission.storage.request();
      }

      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        _showMessage('Gagal download file (status ${response.statusCode})');
        return;
      }

      final uri = Uri.parse(url);
      final fallbackName = uri.path.contains('/patrol/export')
          ? 'riwayat-patroli_${DateTime.now().millisecondsSinceEpoch}.xlsx'
          : 'qrcode_${DateTime.now().millisecondsSinceEpoch}.svg';

      final filename =
          _extractFilename(response.headers['content-disposition']) ??
              fallbackName;

      final savedPath = await _saveToDownloads(filename, response.bodyBytes);

      _showMessage(
        savedPath != null
            ? 'File tersimpan: $filename'
            : 'File tersimpan di penyimpanan aplikasi: $filename',
        filePathToOpen: savedPath,
      );
    } catch (e) {
      _showMessage('Gagal download: $e');
    }
  }

  String? _extractFilename(String? contentDisposition) {
    if (contentDisposition == null) return null;

    // Coba format RFC 5987 dulu: filename*=UTF-8''nama%20file.svg
    // (ini yang dipakai Laravel kalau nama file ada spasi/karakter khusus)
    final encodedMatch =
        RegExp(r"filename\*=UTF-8''([^;]+)").firstMatch(contentDisposition);
    if (encodedMatch != null) {
      return Uri.decodeComponent(encodedMatch.group(1)!.trim());
    }

    // Fallback ke format biasa: filename="nama file.svg"
    final plainMatch =
        RegExp(r'filename="?([^";]+)"?').firstMatch(contentDisposition);
    return plainMatch?.group(1)?.trim();
  }

  Future<String?> _saveToDownloads(String filename, List<int> bytes) async {
    if (Platform.isAndroid) {
      // Folder Download publik di Android.
      final downloadDir = Directory('/storage/emulated/0/Download');

      try {
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }

        final file = File('${downloadDir.path}/$filename');
        await file.writeAsBytes(bytes);
        return file.path;
      } catch (_) {
        // Fallback kalau tidak punya akses tulis langsung
        // (misal Android versi baru tanpa legacy storage).
        final dir = await getExternalStorageDirectory();
        if (dir != null) {
          final file = File('${dir.path}/$filename');
          await file.writeAsBytes(bytes);
          return null;
        }
      }
    }

    // iOS / fallback: simpan ke folder dokumen aplikasi.
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    return null;
  }

  void _showMessage(String message, {String? filePathToOpen}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        action: filePathToOpen != null
            ? SnackBarAction(
                label: 'Buka File',
                onPressed: () {
                  OpenFilex.open(filePathToOpen);
                },
              )
            : null,
      ),
    );
  }

  void _retry() {
    setState(() {
      hasError = false;
      isLoading = true;
      loadingProgress = 0;
    });
    controller.reload();
  }

  // ==== Pull-to-refresh (geser dari atas) ====

  // Posisi Y pointer terakhir, dipakai _onPointerMove untuk menghitung
  // delta gerakan manual (karena Listener tidak kasih delta langsung
  // seperti GestureDetector).
  double? _lastPointerY;

  void _onPointerDown(PointerDownEvent event) {
    _lastPointerY = event.position.dy;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final lastY = _lastPointerY;
    _lastPointerY = event.position.dy;
    if (lastY == null) return;

    final dy = event.position.dy - lastY;

    // Cuma boleh mulai "menarik" kalau: halaman web di posisi paling
    // atas, arah geser ke BAWAH (delta positif), dan bukan lagi
    // proses refresh yang sebelumnya.
    if (!_webViewAtTop || _refreshing || hasError) return;
    if (dy <= 0 && _pullDistance <= 0) return;

    setState(() {
      _pullDistance = (_pullDistance + dy * 0.55).clamp(0, _pullMaxDistance);
    });
  }

  void _onPointerUp(PointerEvent event) {
    _lastPointerY = null;
    _onPullDragEnd();
  }

  Future<void> _onPullDragEnd() async {
    if (_pullDistance >= _pullTriggerThreshold && !_refreshing) {
      setState(() => _refreshing = true);
      controller.reload();
      // Beri jeda sebentar biar animasi loading kelihatan menyatu
      // dengan proses reload yang sebenarnya (onPageStarted/onPageFinished
      // di atas yang akan urus status isLoading selanjutnya).
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _pullDistance = 0;
      });
    } else {
      setState(() => _pullDistance = 0);
    }
  }

  Widget _buildPullToRefreshIndicator() {
    final progress = (_pullDistance / _pullTriggerThreshold).clamp(0.0, 1.0);
    return Positioned(
      top: 10,
      left: 0,
      right: 0,
      child: Center(
        child: Opacity(
          opacity: progress,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: KColors.surfaceContainerLowest,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: KColors.onSurface.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _refreshing
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: KColors.primary,
                    ),
                  )
                : Transform.rotate(
                    angle: progress * 3.14,
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      size: 18,
                      color: progress >= 1
                          ? KColors.primary
                          : KColors.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _webView() {
    return WebViewWidget(controller: controller);
  }

  // Logic back tunggal, dipakai sama-sama oleh:
  // 1. Tombol back Android/gesture (lewat PopScope di build())
  // 2. Tombol menu melayang (_buildFloatingMenuButton)
  // Supaya perilakunya selalu konsisten: cek riwayat halaman web dulu
  // (goBack di dalam WebView), baru keluar WebViewScreen kalau riwayat
  // web-nya udah mentok.
  Future<void> _handleBackAction() async {
    final canGoBack = await controller.canGoBack();

    if (canGoBack) {
      await controller.goBack();
    } else {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  // Aksi dari menu titik tiga:
  // - back   : mundur ke halaman sebelumnya (riwayat WebView dulu, kalau
  //            sudah mentok baru keluar dari WebViewScreen)
  // - portal : kembali ke HomeScreen Flutter (daftar card aplikasi)
  // - quit   : tutup aplikasi
  Future<void> _handleMenuAction(_WebMenuAction action) async {
    switch (action) {
      case _WebMenuAction.back:
        await _handleBackAction();
        break;
      case _WebMenuAction.portal:
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
        break;
      case _WebMenuAction.quit:
        await SystemNavigator.pop();
        break;
    }
  }

  // Clamp posisi tombol supaya tidak pernah kegeser sampai keluar
  // area layar (constraints didapat dari LayoutBuilder pembungkus
  // Stack di body, jadi otomatis menyesuaikan kalau ukuran berubah,
  // misal rotate layar).
  Offset _clampFloatingBackButtonPosition(Offset offset, Size areaSize) {
    final maxX = (areaSize.width - _floatingBackButtonSize).clamp(
      0.0,
      double.infinity,
    );
    final maxY = (areaSize.height - _floatingBackButtonSize).clamp(
      0.0,
      double.infinity,
    );
    return Offset(
      offset.dx.clamp(0.0, maxX),
      offset.dy.clamp(0.0, maxY),
    );
  }

  Widget _buildFloatingMenuButton(Size areaSize) {
    // Posisi awal: pojok kiri-bawah, dikasih sedikit jarak supaya tidak
    // mepet banget ke tepi layar/gesture bar.
    _floatingBackButtonPosition ??= _clampFloatingBackButtonPosition(
      Offset(12, areaSize.height - _floatingBackButtonSize - 90),
      areaSize,
    );

    final position = _clampFloatingBackButtonPosition(
      _floatingBackButtonPosition!,
      areaSize,
    );

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _floatingBackButtonPosition = _clampFloatingBackButtonPosition(
              position + details.delta,
              areaSize,
            );
          });
        },
        child: PopupMenuButton<_WebMenuAction>(
          tooltip: 'Menu',
          padding: EdgeInsets.zero,
          onSelected: _handleMenuAction,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _WebMenuAction.back,
              child: Row(
                children: [
                  Icon(Icons.arrow_back_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('Kembali'),
                ],
              ),
            ),
            PopupMenuItem(
              value: _WebMenuAction.portal,
              child: Row(
                children: [
                  Icon(Icons.home_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('Portal'),
                ],
              ),
            ),
            PopupMenuItem(
              value: _WebMenuAction.quit,
              child: Row(
                children: [
                  Icon(Icons.exit_to_app_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('Keluar Aplikasi'),
                ],
              ),
            ),
          ],
          child: Container(
            width: _floatingBackButtonSize,
            height: _floatingBackButtonSize,
            decoration: BoxDecoration(
              color: KColors.primary,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: KColors.primary.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.menu_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: KColors.surface,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: CircularProgressIndicator(
                    value: loadingProgress > 0 && loadingProgress < 100
                        ? loadingProgress / 100
                        : null,
                    strokeWidth: 3,
                    color: KColors.primary,
                    backgroundColor: KColors.primary.withValues(alpha: 0.12),
                  ),
                ),
                if (loadingProgress > 0 && loadingProgress < 100)
                  Text(
                    '$loadingProgress%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: KColors.primary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Memuat halaman...',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Container(
      color: KColors.surface,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: KColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 32,
                color: KColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Tidak Dapat Terhubung',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: KColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Periksa koneksi internetmu, lalu coba lagi.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: KColors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Coba Lagi',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: KColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackAction();
      },
      child: Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                title: Text(widget.title),
                automaticallyImplyLeading: false,
              )
            : null,
        body: SafeArea(
          top: !widget.showAppBar,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final areaSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              return Stack(
                children: [
                  Listener(
                // PENTING buat performa scroll: pakai Listener (raw pointer),
                // BUKAN GestureDetector. GestureDetector dengan
                // onVerticalDragUpdate/onVerticalDragEnd selalu mendaftar
                // sebagai peserta di gesture arena Flutter untuk SETIAP
                // gesture geser vertikal di area WebView -- termasuk pas
                // scroll biasa di tengah halaman, bukan cuma pas mau pull-
                // to-refresh. Itu bikin native scroll WebView harus
                // "berebut" pengenalan gesture terus-menerus, beda dengan
                // browser biasa yang scroll-nya native murni. Listener
                // tidak ikut disambiguasi gesture arena sama sekali (cuma
                // "menonton" pointer lewat behavior.translucent), jadi
                // WebView selalu dapat native scroll 100% mulus, sementara
                // logic pull-to-refresh dihitung manual dari posisi pointer.
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerUp,
                child: _pullDistance > 0
                    ? Transform.translate(
                        // Transform cuma dipasang SELAMA benar-benar
                        // sedang ditarik (_pullDistance > 0). Membungkus
                        // native view (WebView) dengan Transform terus-
                        // menerus (walau translasinya 0) bisa memaksa
                        // Android merender WebView lewat jalur compositing
                        // yang lebih berat, sehingga scroll kerasa lag
                        // terus-menerus, bukan cuma pas gesture pull aktif.
                        offset: Offset(0, _pullDistance),
                        child: _webView(),
                      )
                    : _webView(),
              ),

              if (_pullDistance > 0) _buildPullToRefreshIndicator(),

              if (isLoading && !hasError)
                AnimatedOpacity(
                  opacity: isLoading ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: _buildLoadingOverlay(),
                ),

              if (hasError) _buildErrorView(),

              // Tombol menu melayang -- SENGAJA ditaruh paling
              // akhir (di atas layer lain) dan TIDAK dibungkus kondisi
              // showAppBar, supaya selalu terlihat & bisa ditap di semua
              // halaman WebView, termasuk saat AppBar disembunyikan.
              _buildFloatingMenuButton(areaSize),
          ],
              );
            },
          ),
        ),
      ),
    );
  }
}