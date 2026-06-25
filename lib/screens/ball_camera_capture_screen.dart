import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/table_guide_geometry.dart';
import '../services/ball_detection_service.dart';
import '../services/camera_preview_mapper.dart';
import '../services/image_bake_service.dart';
import '../services/pending_photo_import_store.dart';
import '../theme/apple_theme.dart';

/// Camera capture with felt trapezoid guide (254×127 cm playing area, near-end view).
class BallCameraCaptureScreen extends StatefulWidget {
  const BallCameraCaptureScreen({super.key});

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<BallCameraCaptureScreen> createState() => _BallCameraCaptureScreenState();
}

class _BallCameraCaptureScreenState extends State<BallCameraCaptureScreen> {
  final _detectionService = BallDetectionService();
  final _previewKey = GlobalKey();

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initializing = true;
  String? _error;
  bool _capturing = false;
  bool _serverOk = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!BallCameraCaptureScreen.isSupported) {
      setState(() {
        _initializing = false;
        _error = 'カメラは Android / iOS アプリで利用できます';
      });
      return;
    }

    _serverOk = await _detectionService.isServerAvailable();
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw StateError('カメラが見つかりません');
      }
      final back = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'カメラを起動できません: $e';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureAndDetect() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    if (!_serverOk) {
      _showSnack('検出 API が未起動です (127.0.0.1:8765)');
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
      final widgetSize = previewBox.size;
      final guideNorm = TableGuideGeometry.guideCornersNormalized();
      final corners = CameraPreviewMapper.mapGuideToNormalizedImage(
        guideWidgetNorm: guideNorm,
        widgetSize: widgetSize,
        imageSize: baked.size,
      );
      final ySpan = CameraPreviewMapper.cornerYSpan(corners);
      if (ySpan < 0.35) {
        throw StateError(
          'ガイド座標の変換が不正です (y幅=${ySpan.toStringAsFixed(2)})。'
          'もう一度撮影してください',
        );
      }

      final layout = await _detectionService.detectFromBytes(
        imageBytes: baked.bytes,
        filename: 'capture.png',
        refWidth: baked.size.width,
        refHeight: baked.size.height,
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
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
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

    final controller = _controller!;
    return Column(
      children: [
        Material(
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
                      : 'API 未接続 — 撮影のみ（検出不可）',
                  style: TextStyle(
                    color: _serverOk ? Colors.white : Colors.orange.shade200,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
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
                  onPressed: (_capturing || !_serverOk) ? null : _captureAndDetect,
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
