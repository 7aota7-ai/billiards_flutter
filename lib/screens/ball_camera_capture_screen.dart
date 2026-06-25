import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/table_guide_geometry.dart';
import '../services/ball_detection_service.dart';
import '../services/camera_preview_mapper.dart';
import '../services/image_bake_service.dart';
import '../services/pending_photo_import_store.dart';
import '../theme/apple_theme.dart';

/// Camera capture with felt trapezoid guide (254×127 cm playing area, near-end view).
///
/// Web (HTTPS): live preview after user taps start (browser requires user gesture).
/// Fallback: [ImagePicker] opens the device camera on mobile browsers.
class BallCameraCaptureScreen extends StatefulWidget {
  const BallCameraCaptureScreen({super.key});

  @override
  State<BallCameraCaptureScreen> createState() => _BallCameraCaptureScreenState();
}

class _BallCameraCaptureScreenState extends State<BallCameraCaptureScreen> {
  final _detectionService = BallDetectionService();
  final _previewKey = GlobalKey();
  final _imagePicker = ImagePicker();

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initializing = false;
  bool _awaitingWebStart = kIsWeb;
  String? _error;
  bool _capturing = false;
  bool _serverOk = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _refreshServerStatus();
    } else {
      _initializing = true;
      _init();
    }
  }

  Future<void> _refreshServerStatus() async {
    final ok = await _detectionService.isServerAvailable();
    if (!mounted) return;
    setState(() => _serverOk = ok);
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
      _serverOk = await _detectionService.isServerAvailable();
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
      return 'ライブプレビューを起動できませんでした。\n'
          '下の「ブラウザカメラで撮影」を試すか、再試行してください。\n\n'
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

  List<List<double>> _guideCornersNormalizedLists() {
    return TableGuideGeometry.guideCornersNormalized()
        .map((p) => [p.dx, p.dy])
        .toList(growable: false);
  }

  Future<void> _detectFromBytes({
    required Uint8List bytes,
    required Size imageSize,
    required List<List<double>> corners,
  }) async {
    if (!_serverOk) {
      throw StateError(
        '検出 API が未接続です。PC で tools/ball_detector の API を起動し、'
        '同一 Wi‑Fi から PC の IP:8765 へ届く必要があります。',
      );
    }
    final ySpan = CameraPreviewMapper.cornerYSpan(corners);
    if (ySpan < 0.35) {
      throw StateError(
        'ガイド座標が不正です (y幅=${ySpan.toStringAsFixed(2)})。'
        'もう一度撮影してください',
      );
    }
    final layout = await _detectionService.detectFromBytes(
      imageBytes: bytes,
      filename: 'capture.png',
      refWidth: imageSize.width,
      refHeight: imageSize.height,
      corners: corners.map((p) => OffsetLike(p[0], p[1])).toList(),
    );
    if (layout.balls.isEmpty) {
      throw StateError('0 球 — 枠合わせを確認して再撮影してください');
    }
    PendingPhotoImportStore.set(layout);
    if (!mounted) return;
    await Navigator.of(context).pushNamedAndRemoveUntil(
      '/layout',
      (route) =>
          route.settings.name == '/setup' ||
          route.settings.name == '/' ||
          route.isFirst,
    );
  }

  Future<void> _captureAndDetect() async {
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
      await _detectFromBytes(
        bytes: baked.bytes,
        imageSize: baked.size,
        corners: corners,
      );
    } on BallDetectionException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('$e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Mobile browser fallback when live preview is unavailable.
  Future<void> _captureViaBrowserPicker() async {
    if (_capturing) return;
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
      await _detectFromBytes(
        bytes: baked.bytes,
        imageSize: baked.size,
        corners: _guideCornersNormalizedLists(),
      );
    } on BallDetectionException catch (e) {
      _showSnack(e.message);
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
      return _buildWebStartGate();
    }
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
      return _buildErrorPanel(showBrowserPicker: kIsWeb);
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
                  onPressed: _capturing ? null : _captureAndDetect,
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
                  label: Text(_capturing ? '処理中…' : '撮影して検出'),
                ),
              ],
            ),
          ),
        ),
      ],
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
              '黄色枠に台を合わせて撮影します。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (!_serverOk) ...[
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
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              onPressed: _capturing ? null : _captureViaBrowserPicker,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('ブラウザカメラで撮影'),
            ),
            const SizedBox(height: 10),
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
                  ? '黄色枠にフェルト4隅が収まるよう合わせて撮影'
                  : 'API 未接続 — 撮影のみ（検出には PC の API が必要）',
              style: TextStyle(
                color: _serverOk ? Colors.white : Colors.orange.shade200,
                fontSize: 13,
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
