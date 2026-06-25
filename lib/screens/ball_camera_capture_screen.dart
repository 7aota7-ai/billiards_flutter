import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/table_guide_geometry.dart';
import '../services/ball_detection_service.dart';
import '../services/camera_preview_mapper.dart';
import '../services/detection_api_settings.dart';
import '../services/image_bake_service.dart';
import '../services/pending_capture_store.dart';
import '../theme/apple_theme.dart';
import '../utils/web_platform.dart';

/// Camera capture with felt trapezoid guide (254×127 cm playing area, near-end view).
///
/// Web (HTTPS, smartphone): live preview after user taps start.
/// Fallback: [ImagePicker] with `capture=environment` on mobile browsers only.
/// Desktop browsers: use photo import (camera opens a folder dialog here).
class BallCameraCaptureScreen extends StatefulWidget {
  const BallCameraCaptureScreen({super.key});

  @override
  State<BallCameraCaptureScreen> createState() => _BallCameraCaptureScreenState();
}

class _BallCameraCaptureScreenState extends State<BallCameraCaptureScreen> {
  BallDetectionService _detectionService =
      BallDetectionService(baseUrl: DetectionApiSettings.defaultUrl);
  final _previewKey = GlobalKey();
  final _imagePicker = ImagePicker();

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initializing = false;
  bool _awaitingWebStart = kIsWeb;
  String? _error;
  bool _capturing = false;
  bool _serverOk = false;
  BallDetectionServerStatus _serverStatus = const BallDetectionServerStatus(
    available: false,
    summary: '検出 API: 確認中…',
  );

  @override
  void initState() {
    super.initState();
    _initApi();
    if (!kIsWeb) {
      _initializing = true;
      _init();
    }
  }

  Future<void> _initApi() async {
    final url = await DetectionApiSettings.loadBaseUrl();
    if (!mounted) return;
    setState(() {
      _detectionService = BallDetectionService(baseUrl: url);
    });
    if (kIsWeb) {
      await _refreshServerStatus();
    }
  }

  Future<void> _refreshServerStatus() async {
    final status = await _detectionService.checkServer();
    if (!mounted) return;
    setState(() {
      _serverStatus = status;
      _serverOk = status.available;
    });
  }

  Future<void> _startCameraFromUserGesture() async {
    setState(() {
      _awaitingWebStart = false;
      _initializing = true;
      _error = null;
    });
    await _init();
  }

  Future<void> _init() async {
    if (!_awaitingWebStart) {
      await _refreshServerStatus();
    }
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw StateError('カメラが見つかりません');
      }
      final back = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
      const preset =
          kIsWeb ? ResolutionPreset.medium : ResolutionPreset.high;
      await _openController(back, preset);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = _formatInitError(e);
      });
    }
  }

  String _formatInitError(Object e) {
    if (kIsWeb) {
      if (isDesktopWeb) {
        return 'PC ブラウザではライブプレビューが使えないことが多いです。\n'
            '「写真から読込」でテストするか、スマホ Web で撮影してください。\n\n'
            '詳細: $e';
      }
      return 'ライブプレビューを起動できませんでした。\n'
          '「ブラウザカメラで撮影」を試すか、再試行してください。\n\n'
          '※ HTTPS の URL から開いてください（GitHub Pages は OK）\n'
          '※ ブラウザのカメラ許可が必要です\n\n'
          '詳細: $e';
    }
    return 'カメラを起動できません (${defaultTargetPlatform.name})。\n'
        '設定でカメラ権限を確認してください。\n\n'
        '詳細: $e';
  }

  Future<void> _openController(
    CameraDescription camera,
    ResolutionPreset preset,
  ) async {
    final controller = CameraController(
      camera,
      preset,
      enableAudio: false,
      imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
          ? ImageFormatGroup.jpeg
          : null,
    );
    try {
      await controller.initialize();
    } on CameraException catch (_) {
      await controller.dispose();
      if (preset != ResolutionPreset.medium) {
        await _openController(camera, ResolutionPreset.medium);
        return;
      }
      rethrow;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller?.dispose();
      _controller = controller;
      _initializing = false;
      _error = null;
    });
  }

  Future<void> _retryInit() async {
    setState(() {
      _awaitingWebStart = false;
      _initializing = true;
      _error = null;
    });
    await _controller?.dispose();
    _controller = null;
    await _init();
  }

  Future<void> _captureAndReview() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }

    final previewBox =
        _previewKey.currentContext?.findRenderObject() as RenderBox?;
    if (previewBox == null) {
      _showSnack('プレビューの準備中です');
      return;
    }

    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      final raw = await file.readAsBytes();
      final baked = await ImageBakeService.bake(raw);
      final corners = CameraPreviewMapper.mapGuideToNormalizedImage(
        guideWidgetNorm: TableGuideGeometry.guideCornersNormalized(),
        widgetSize: previewBox.size,
        imageSize: baked.size,
      );
      await _handoffToPhotoImport(
        bytes: baked.bytes,
        imageSize: baked.size,
        corners: corners,
      );
    } catch (e) {
      _showSnack('$e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Photo import でプレビュー＋4隅微調整してから検出する。
  Future<void> _handoffToPhotoImport({
    required Uint8List bytes,
    required Size imageSize,
    required List<List<double>> corners,
  }) async {
    PendingCaptureStore.set(
      bytes: bytes,
      imageSize: imageSize,
      cornersNormalized: corners,
    );
    if (!mounted) return;
    await Navigator.of(context).pushReplacementNamed('/photo-import');
  }

  Future<void> _captureViaBrowserPicker() async {
    if (_capturing) return;
    if (isDesktopWeb) {
      _showSnack('PC ブラウザではカメラ撮影非対応です。「写真から読込」を使ってください');
      return;
    }
    setState(() => _capturing = true);
    try {
      if (kIsWeb && !_serverOk) {
        await _refreshServerStatus();
      }
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (picked == null) return;
      final raw = await picked.readAsBytes();
      final baked = await ImageBakeService.bake(raw);
      await _handoffToPhotoImport(
        bytes: baked.bytes,
        imageSize: baked.size,
        corners: TableGuideGeometry.defaultPhotoCornersAsLists(),
      );
    } catch (e) {
      _showSnack('$e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: buildAppleGlassAppBar(
        context,
        title: '配置を取る',
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: AppleColors.textOnDark,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_awaitingWebStart) {
      return isDesktopWeb ? _buildDesktopWebGate() : _buildWebStartGate();
    }
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
      return _buildErrorPanel(
        showBrowserPicker: kIsWeb && supportsBrowserCameraCapture,
      );
    }

    final controller = _controller!;
    return Column(
      children: [
        _buildHintBar(),
        Expanded(
          key: _previewKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(controller),
              CustomPaint(
                painter: _TableGuidePainter(
                  corners: TableGuideGeometry.guideCornersNormalized(),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _capturing ? null : _captureAndReview,
                  icon: _capturing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.camera_alt),
                  label: Text(_capturing ? '処理中…' : '撮影して確認'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopWebGate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smartphone, color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            Text(
              TableGuideGeometry.specLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 8),
            const Text(
              'PC ブラウザ（localhost 含む）では\n'
              'カメラプレビュー・「ブラウザカメラで撮影」は使えません\n'
              '（フォルダ選択が開く仕様です）。\n\n'
              '黄色ガイド付き撮影 → スマホ Web（HTTPS）\n'
              '球検出テスト → PC の「写真から読込」',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            if (!_serverOk && _serverStatus.detail != null) ...[
              const SizedBox(height: 12),
              Text(
                _serverStatus.detail!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange.shade200, fontSize: 12),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushReplacementNamed('/photo-import'),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('写真から読込へ'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _startCameraFromUserGesture,
              child: const Text(
                'それでもプレビューを試す',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebStartGate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam, color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            Text(
              TableGuideGeometry.specLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 8),
            const Text(
              'Web でもカメラを使えます（App Store 不要）。\n'
              'HTTPS の URL から開き、カメラ許可を与えてください。\n'
              '黄色枠に台を合わせて撮影 → 4隅を確認して検出します。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (!_serverOk && _serverStatus.detail != null) ...[
              const SizedBox(height: 12),
              Text(
                _serverStatus.detail!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange.shade200, fontSize: 12),
              ),
            ] else if (!_serverOk) ...[
              const SizedBox(height: 12),
              Text(
                '検出 API 未接続 — 撮影のみ可能（球検出は PC の API が必要）',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange.shade200, fontSize: 12),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _startCameraFromUserGesture,
              icon: const Icon(Icons.videocam),
              label: const Text('カメラプレビューを起動'),
            ),
            const SizedBox(height: 10),
            if (supportsBrowserCameraCapture)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                onPressed: _capturing ? null : _captureViaBrowserPicker,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('ブラウザカメラで撮影'),
              ),
            if (supportsBrowserCameraCapture) const SizedBox(height: 10),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pushReplacementNamed('/photo-import'),
              child: const Text('写真から読込へ', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorPanel({required bool showBrowserPicker}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 20),
            if (showBrowserPicker)
              FilledButton.icon(
                onPressed: _capturing ? null : _captureViaBrowserPicker,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('ブラウザカメラで撮影'),
              ),
            if (showBrowserPicker) const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _retryInit,
              child: const Text('プレビューを再試行'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              onPressed: () => Navigator.of(context).pushReplacementNamed(
                '/photo-import',
              ),
              child: const Text('写真から読込へ'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHintBar() {
    return Material(
      color: const Color(0xFF1B1B1B),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              TableGuideGeometry.specLabel,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              _serverOk
                  ? '黄色枠に合わせて撮影 → 次画面で4隅を確認して検出'
                  : _serverStatus.summary,
              style: TextStyle(
                color: _serverOk ? Colors.white : Colors.orange.shade200,
                fontSize: 13,
              ),
            ),
            if (!_serverOk && _serverStatus.detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _serverStatus.detail!,
                  style: TextStyle(
                    color: Colors.orange.shade100,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TableGuidePainter extends CustomPainter {
  _TableGuidePainter({required this.corners});

  final List<Offset> corners;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = corners
        .map(
          (c) => Offset(c.dx * size.width, c.dy * size.height),
        )
        .toList(growable: false);

    final hole = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();

    final outer = Path()..addRect(Offset.zero & size);
    final dimPath = Path.combine(PathOperation.difference, outer, hole);
    canvas.drawPath(
      dimPath,
      Paint()..color = const Color(0xAA000000),
    );

    final border = Paint()
      ..color = const Color(0xFFFFEB3B)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawPath(hole, border);

    const labels = ['遠L', '遠R', '手R', '手L'];
    for (var i = 0; i < pts.length; i++) {
      canvas.drawCircle(pts[i], 6, Paint()..color = const Color(0xFFFFEB3B));
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pts[i] + const Offset(8, -16));
    }
  }

  @override
  bool shouldRepaint(covariant _TableGuidePainter oldDelegate) => false;
}
