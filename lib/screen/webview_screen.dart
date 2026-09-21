import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show Factory;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'home_screen.dart';

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
    this.addMobileAppParam = true,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController controller;
  bool isLoading = true;
  int loadingProgress = 0;
  bool hasError = false;

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
                var reportScroll = function() {
                  var atTop = (window.scrollY || document.documentElement.scrollTop || 0) <= 0;
                  FlutterScrollTracker.postMessage(atTop ? 'top' : 'nottop');
                };
                window.addEventListener('scroll', reportScroll, { passive: true });
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

  void _onPullDragUpdate(DragUpdateDetails details) {
    // Cuma boleh mulai "menarik" kalau: halaman web di posisi paling
    // atas, arah geser ke BAWAH (delta positif), dan bukan lagi
    // proses refresh yang sebelumnya.
    if (!_webViewAtTop || _refreshing || hasError) return;
    if (details.delta.dy <= 0 && _pullDistance <= 0) return;

    setState(() {
      _pullDistance = (_pullDistance + details.delta.dy * 0.55)
          .clamp(0, _pullMaxDistance);
    });
  }

  Future<void> _onPullDragEnd(DragEndDetails details) async {
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

        final canGoBack = await controller.canGoBack();

        if (canGoBack) {
          await controller.goBack();
        } else {
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
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
          child: Stack(
          children: [
            GestureDetector(
              onVerticalDragUpdate: _onPullDragUpdate,
              onVerticalDragEnd: _onPullDragEnd,
              child: Transform.translate(
                offset: Offset(0, _pullDistance),
                child: WebViewWidget(
                  controller: controller,
                  // gestureRecognizers ini yang bikin gesture geser bisa
                  // "kedengaran" juga sama GestureDetector di atas,
                  // meskipun jari user lagi nyentuh area WebView (yang
                  // biasanya WebView native "monopoli" semua sentuhan).
                  gestureRecognizers: {
                    Factory<VerticalDragGestureRecognizer>(
                      () => VerticalDragGestureRecognizer(),
                    ),
                  },
                ),
              ),
            ),

            if (_pullDistance > 0) _buildPullToRefreshIndicator(),

            if (isLoading && !hasError)
              AnimatedOpacity(
                opacity: isLoading ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: _buildLoadingOverlay(),
              ),

            if (hasError) _buildErrorView(),
          ],
          ),
        ),
      ),
    );
  }
}