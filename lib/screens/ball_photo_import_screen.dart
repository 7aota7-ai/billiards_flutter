import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../models/detected_ball_layout.dart';
import '../services/ball_detection_service.dart';
import '../services/detection_api_settings.dart';
import '../services/pending_capture_store.dart';
import '../services/pending_photo_import_store.dart';
import '../services/picked_file_reader.dart';
import '../theme/apple_theme.dart';

/// Semi-automatic photo import: pick image, tap 4 felt corners, detect balls.
class BallPhotoImportScreen extends StatefulWidget {
  const BallPhotoImportScreen({super.key});

  @override
  State<BallPhotoImportScreen> createState() => _BallPhotoImportScreenState();
}

class _BallPhotoImportScreenState extends State<BallPhotoImportScreen> {
  static const _cornerLabels = [
    '① 遠い側・左（画像の上、y≈0.15）',
    '② 遠い側・右',
    '③ 手前・右（下までスクロール、y≈0.85）',
    '④ 手前・左',
  ];

  /// Reference felt corners for table_photo-like portrait shots (normalized).
  static const _guideCorners = <Offset>[
    Offset(0.254, 0.151),
    Offset(0.749, 0.151),
    Offset(0.892, 0.864),
    Offset(0.111, 0.864),
  ];

  BallDetectionService _service =
      BallDetectionService(baseUrl: DetectionApiSettings.defaultUrl);
  final _jsonCtrl = TextEditingController();

  Uint8List? _imageBytes;
  String? _filename;
  Size? _imageSize;
  final List<Offset> _corners = [];
  DetectedBallLayout? _result;
  bool _busy = false;
  bool _picking = false;
  String? _status;
  bool _serverOk = false;
  BallDetectionServerStatus _serverStatus = const BallDetectionServerStatus(
    available: false,
    summary: '検出 API: 確認中…',
  );
  bool _jsonExpanded = false;
  bool _showGuides = true;

  @override
  void initState() {
    super.initState();
    _initApi();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPendingCapture());
  }

  @override
  void dispose() {
    _jsonCtrl.dispose();
    super.dispose();
  }

  Future<void> _initApi() async {
    final url = await DetectionApiSettings.loadBaseUrl();
    if (!mounted) return;
    setState(() {
      _service = BallDetectionService(baseUrl: url);
    });
    await _checkServer();
  }

  Future<void> _checkServer() async {
    final status = await _service.checkServer();
    if (!mounted) return;
    setState(() {
      _serverStatus = status;
      _serverOk = status.available;
    });
  }

  void _loadPendingCapture() {
    final cap = PendingCaptureStore.take();
    if (cap == null) return;
    setState(() {
      _imageBytes = cap.bytes;
      _imageSize = cap.imageSize;
      _filename = 'capture.jpg';
      _corners.clear();
      final norm = cap.cornersNormalized;
      if (norm != null && norm.length == 4) {
        for (final p in norm) {
          _corners.add(Offset(
            p[0] * cap.imageSize.width,
            p[1] * cap.imageSize.height,
          ));
        }
        _updateCornerStatus();
        _status = 'カメラ撮影を引き継ぎ — API で検出できます';
      } else {
        _status = 'カメラ撮影を引き継ぎ — 4隅をタップしてください';
      }
    });
  }

  int? _metaInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  String _formatDetectionStatus({
    required DetectedBallLayout layout,
    String? mode,
    String? imgSize,
  }) {
    final meta = layout.meta;
    final raw = _metaInt(meta['ball_count_raw']);
    final hasFilterMeta = meta['filter'] is Map;
    final suffix = '($mode · img=$imgSize)';

    if (raw != null && raw > layout.balls.length) {
      return '${layout.balls.length} 球を検出（フィルタ前 $raw 個） $suffix';
    }
    if (!hasFilterMeta && layout.balls.length > 15) {
      return '${layout.balls.length} 球を検出 — API v0.1.3 未適用？ '
          'uvicorn を再起動してください $suffix';
    }
    return '${layout.balls.length} 球を検出 $suffix';
  }

  Future<void> _pickImage() async {
    if (_picking || _busy) return;
    setState(() {
      _picking = true;
      _status = 'ファイル選択中…';
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        setState(() => _status = '写真選択がキャンセルされました');
        return;
      }

      final picked = result.files.single;
      final rawBytes = await readPlatformFileBytes(picked);
      if (rawBytes == null || rawBytes.isEmpty) {
        throw StateError('画像データを読み込めませんでした');
      }

      final bakedBytes = await _bakeImageBytes(rawBytes);
      await _decodeImageSize(bakedBytes);
      if (!mounted) return;
      setState(() {
        _imageBytes = bakedBytes;
        _filename = picked.name.endsWith('.png')
            ? picked.name
            : '${picked.name.replaceAll(RegExp(r'\.[^.]+$'), '')}.png';
        _corners.clear();
        _result = null;
        _status = '4隅を順番にタップしてください（左上→右上→右下→左下）';
      });
    } catch (e) {
      if (!mounted) return;
      final msg = '写真を開けませんでした: $e';
      setState(() => _status = msg);
      _showSnack(msg);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Bake EXIF orientation into pixels so Flutter display == OpenCV decode.
  Future<Uint8List> _bakeImageBytes(Uint8List raw) async {
    final codec = await ui.instantiateImageCodec(raw);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final w = img.width;
    final h = img.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(img, Offset.zero, Paint());
    final picture = recorder.endRecording();
    final baked = await picture.toImage(w, h);
    final data = await baked.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    baked.dispose();
    if (data == null) {
      throw StateError('画像の正規化に失敗しました');
    }
    return data.buffer.asUint8List();
  }

  Future<void> _decodeImageSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    _imageSize = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
  }

  /// Fit image to [boxWidth]; height follows aspect ratio (scrollable if tall).
  _ImageLayout _imageLayoutForWidth(double boxWidth) {
    final imageSize = _imageSize!;
    if (boxWidth <= 0) return _ImageLayout.zero;
    final scale = boxWidth / imageSize.width;
    final renderSize = Size(boxWidth, imageSize.height * scale);
    return _ImageLayout(renderSize: renderSize, offset: Offset.zero, scale: scale);
  }

  void _addCornerFromLocal(Offset local, Size renderSize) {
    if (_imageSize == null || _corners.length >= 4) return;
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx > renderSize.width ||
        local.dy > renderSize.height) {
      return;
    }

    final imagePoint = Offset(
      local.dx / renderSize.width * _imageSize!.width,
      local.dy / renderSize.height * _imageSize!.height,
    );
    _commitCorner(imagePoint);
  }

  void _commitCorner(Offset imagePoint) {
    setState(() {
      _corners.add(imagePoint);
      if (_corners.length == 4) {
        _updateCornerStatus();
      } else {
        _status = '${_cornerLabels[_corners.length]} をタップ';
      }
    });
  }

  Future<void> _openFullscreenPicker() async {
    if (_imageBytes == null || _imageSize == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _FullscreenCornerPicker(
          imageBytes: _imageBytes!,
          imageSize: _imageSize!,
          cornerLabels: _cornerLabels,
          guideCorners: _guideCorners,
          initialCorners: List<Offset>.from(_corners),
          onDone: (corners) {
            setState(() {
              _corners
                ..clear()
                ..addAll(corners);
              if (_corners.length == 4) {
                _updateCornerStatus();
              }
            });
          },
        ),
      ),
    );
  }

  void _updateCornerStatus() {
    final norm = _normalizedCorners();
    final ys = norm.map((p) => p[1]).toList();
    final ySpan = ys.reduce((a, b) => a > b ? a : b) -
        ys.reduce((a, b) => a < b ? a : b);
    final spanHint = ySpan < 0.35
        ? '\n⚠ 縦方向が狭すぎます（y幅=${ySpan.toStringAsFixed(2)}）。'
            '遠い側 y≈0.15 / 手前側 y≈0.85 を目安に'
        : '';
    _status =
        '4点完了 (${_imageSize!.width.toInt()}×${_imageSize!.height.toInt()})\n'
        'corners: ${norm.map((p) => '(${p[0].toStringAsFixed(3)},${p[1].toStringAsFixed(3)})').join(' ')}'
        '$spanHint';
  }

  bool get _cornerSpanOk {
    if (_corners.length != 4 || _imageSize == null) return false;
    final ys = _normalizedCorners().map((p) => p[1]);
    final ySpan = ys.reduce((a, b) => a > b ? a : b) -
        ys.reduce((a, b) => a < b ? a : b);
    return ySpan >= 0.35;
  }

  List<List<double>> _normalizedCorners() {
    final w = _imageSize!.width;
    final h = _imageSize!.height;
    return _corners
        .map((p) => [(p.dx / w).clamp(0.0, 1.0), (p.dy / h).clamp(0.0, 1.0)])
        .toList(growable: false);
  }

  Future<void> _runDetection() async {
    if (_imageBytes == null || _corners.length != 4) return;
    if (!_cornerSpanOk) {
      _showSnack('4隅が台全体を囲えていません。全画面で打ち直すか、遠い角→手前角まで広げてください');
      return;
    }
    setState(() {
      _busy = true;
      _status = '検出中…';
    });
    try {
      DetectedBallLayout layout;
      if (_serverOk) {
        layout = await _service.detectFromBytes(
          imageBytes: _imageBytes!,
          filename: _filename ?? 'photo.jpg',
          refWidth: _imageSize!.width,
          refHeight: _imageSize!.height,
          corners: _normalizedCorners()
              .map((p) => OffsetLike(p[0], p[1]))
              .toList(growable: false),
        );
      } else {
        throw BallDetectionException(
          '検出 API が起動していません。tools/ball_detector で uvicorn を起動するか、CLI の JSON を貼り付けてください。',
        );
      }
      if (!mounted) return;
      final meta = layout.meta;
      final imgSize = meta['image_size'];
      final refSize = meta['ref_size'];
      final cornersOk = meta['corners_ok'];
      final mode = meta['detect_mode'];
      final uploadBytes = meta['upload_bytes'];
      setState(() {
        _result = layout;
        _jsonCtrl.text = const JsonEncoder.withIndent('  ').convert({
          'balls': layout.balls.map((b) => b.toJson()).toList(),
          'meta': layout.meta,
        });
        if (layout.balls.isEmpty) {
          _status = '0 球 — 画像サイズ $imgSize / Flutter $refSize / '
              '${uploadBytes ?? '?'} bytes\n'
              '4隅OK=${cornersOk ?? '?'} mode=$mode\n'
              '4隅をやり直すか、JSON 貼り付けを試してください';
          _showSnack(
            cornersOk == false
                ? '4隅が近すぎます。フェルトの4隅を広げてタップし直してください'
                : '0 球: tools/ball_detector/samples/out/last_detect.json を確認',
          );
        } else {
          _status = _formatDetectionStatus(
            layout: layout,
            mode: mode?.toString(),
            imgSize: imgSize?.toString(),
          );
        }
      });
    } on BallDetectionException catch (e) {
      if (!mounted) return;
      setState(() => _status = e.message);
      _showSnack(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'エラー: $e');
      _showSnack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _importJson() {
    try {
      final layout = _service.parseJson(_jsonCtrl.text.trim());
      if (layout.balls.isEmpty) {
        _showSnack('balls が空です。CLI の result.json を貼り付けてください');
        return;
      }
      setState(() {
        _result = layout;
        _status = 'JSON を読み込み (${layout.balls.length} 球)';
      });
    } on FormatException catch (e) {
      _showSnack(
        'JSON が不正です。README の [...] 省略例は使えません。\n'
        'tools/ball_detector/samples/paste_example.json をコピーしてください。\n$e',
      );
    } catch (e) {
      _showSnack('JSON の解析に失敗: $e');
    }
  }

  void _loadSampleJson() {
    const sample = '''
{
  "balls": [
    {"id": null, "x": 0.312, "y": 0.548, "color": "yellow"},
    {"id": null, "x": 0.697, "y": 0.241, "color": "white"},
    {"id": null, "x": 0.159, "y": 0.271, "color": "purple"},
    {"id": null, "x": 0.858, "y": 0.483, "color": "orange"},
    {"id": null, "x": 0.380, "y": 0.563, "color": "red"},
    {"id": null, "x": 0.794, "y": 0.451, "color": "black"},
    {"id": null, "x": 0.450, "y": 0.098, "color": "blue"},
    {"id": null, "x": 0.776, "y": 0.397, "color": "maroon"}
  ]
}''';
    _jsonCtrl.text = sample;
    _importJson();
  }

  Future<void> _applyAndReturn() async {
    if (_result == null || _result!.balls.isEmpty) {
      _showSnack('検出結果がありません');
      return;
    }
    PendingPhotoImportStore.set(_result!);
    if (!mounted) return;
    await Navigator.of(context).pushNamedAndRemoveUntil(
      '/layout',
      (route) =>
          route.settings.name == '/setup' ||
          route.settings.name == '/' ||
          route.isFirst,
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppleGlassAppBar(
        context,
        title: '写真から読込',
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: AppleColors.textOnDark,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusBanner(),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: (_busy || _picking) ? null : _pickImage,
                    icon: _picking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_library_outlined),
                    label: Text(_picking ? '選択中…' : '写真を選択'),
                  ),
                  OutlinedButton(
                    onPressed: _corners.isEmpty
                        ? null
                        : () => setState(() {
                              _corners.clear();
                              _result = null;
                              _status = '4隅を順番にタップしてください';
                            }),
                    child: const Text('4点リセット'),
                  ),
                  FilledButton(
                    onPressed: (_busy || _corners.length != 4 || !_serverOk)
                        ? null
                        : _runDetection,
                    child: Text(_busy ? '検出中…' : 'API で検出'),
                  ),
                  if (_imageBytes != null)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _openFullscreenPicker,
                      icon: const Icon(Icons.fullscreen, size: 18),
                      label: const Text('全画面で4隅'),
                    ),
                ],
              ),
              if (_imageBytes != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '黄色=目安位置。③④は BRUNSWICK 付近（y≈0.85）まで下へ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.black54,
                            ),
                      ),
                    ),
                    FilterChip(
                      label: const Text('目安表示'),
                      selected: _showGuides,
                      onSelected: (v) => setState(() => _showGuides = v),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(child: _buildCornerPicker()),
              ] else
                const Expanded(
                  child: Center(
                    child: Text(
                      '写真を選ぶと、ここに全体が表示されます。\n'
                      '4隅はフェルト内側の角を順番にタップしてください。',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              if (_result != null) ...[
                Material(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '検出プレビュー: ${_result!.balls.length} 球',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _applyAndReturn,
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('エディタへ反映'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: _jsonExpanded,
                onExpansionChanged: (v) => setState(() => _jsonExpanded = v),
                title: Text(
                  'CLI JSON 貼り付け（API 未起動時）',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                children: [
                  SizedBox(
                    height: 100,
                    child: TextField(
                      controller: _jsonCtrl,
                      maxLines: null,
                      expands: true,
                      decoration: const InputDecoration(
                        hintText:
                            '{"balls":[{"id":null,"x":0.3,"y":0.5,"color":"yellow"}]}',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: _importJson,
                        child: const Text('JSON 読込'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _loadSampleJson,
                        child: const Text('サンプル JSON'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _serverOk ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_serverStatus.summary, style: const TextStyle(fontSize: 13)),
          if (_serverStatus.detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _serverStatus.detail!,
                style: const TextStyle(fontSize: 12, height: 1.35),
              ),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_status!, style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _buildCornerPicker() {
    final imageSize = _imageSize!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _corners.isEmpty
              ? '① をタップ — 緑の丸が付けば OK'
              : _corners.length < 4
                  ? '次: ${_cornerLabels[_corners.length]}（${_corners.length}/4 点）'
                  : '4点完了 — 緑の数値が API 送信座標',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = _imageLayoutForWidth(constraints.maxWidth);
              return SingleChildScrollView(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) =>
                      _addCornerFromLocal(d.localPosition, layout.renderSize),
                  child: SizedBox(
                    width: layout.renderSize.width,
                    height: layout.renderSize.height,
                    child: Stack(
                      children: [
                        Image.memory(
                          _imageBytes!,
                          width: layout.renderSize.width,
                          height: layout.renderSize.height,
                          fit: BoxFit.fill,
                        ),
                        CustomPaint(
                          size: layout.renderSize,
                          painter: _CornerOverlayPainter(
                            corners: _corners,
                            imageSize: imageSize,
                            renderSize: layout.renderSize,
                            guideCorners: _showGuides ? _guideCorners : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ImageLayout {
  const _ImageLayout({
    required this.renderSize,
    required this.offset,
    this.scale = 1,
  });

  final Size renderSize;
  final Offset offset;
  final double scale;

  static const zero = _ImageLayout(renderSize: Size.zero, offset: Offset.zero);
}

class _CornerOverlayPainter extends CustomPainter {
  _CornerOverlayPainter({
    required this.corners,
    required this.imageSize,
    required this.renderSize,
    this.guideCorners,
  });

  final List<Offset> corners;
  final Size imageSize;
  final Size renderSize;
  final List<Offset>? guideCorners;

  Offset _toRender(Offset imagePoint) => Offset(
        imagePoint.dx / imageSize.width * renderSize.width,
        imagePoint.dy / imageSize.height * renderSize.height,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final guides = guideCorners;
    if (guides != null && guides.length == 4) {
      final guidePaint = Paint()
        ..color = const Color(0x88FFEB3B)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      for (final yNorm in [0.151, 0.864]) {
        final y = yNorm * renderSize.height;
        canvas.drawLine(Offset(0, y), Offset(renderSize.width, y), guidePaint);
      }
      const guideLabels = ['遠L', '遠R', '手R', '手L'];
      for (var i = 0; i < 4; i++) {
        final pt = _toRender(
          Offset(guides[i].dx * imageSize.width, guides[i].dy * imageSize.height),
        );
        canvas.drawCircle(pt, 14, guidePaint);
        final tp = TextPainter(
          text: TextSpan(
            text: guideLabels[i],
            style: const TextStyle(color: Color(0xFFFFEB3B), fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, pt + const Offset(-10, -20));
      }
    }

    if (corners.isEmpty) return;

    final stroke = Paint()
      ..color = const Color(0xFF00E676)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final pts = corners.map(_toRender).toList(growable: false);

    // Dashed hint toward the next guide corner (before all 4 are placed).
    if (guides != null && guides.length == 4 && corners.length < 4) {
      final nextGuide = _toRender(
        Offset(
          guides[corners.length].dx * imageSize.width,
          guides[corners.length].dy * imageSize.height,
        ),
      );
      _drawDashedLine(canvas, pts.last, nextGuide, stroke);
    }

    for (var i = 0; i < pts.length; i++) {
      canvas.drawCircle(pts[i], 12, Paint()..color = const Color(0x6600E676));
      canvas.drawCircle(pts[i], 12, stroke);
      final normX = (corners[i].dx / imageSize.width).clamp(0.0, 1.0);
      final normY = (corners[i].dy / imageSize.height).clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text:
              '${i + 1}\n(${normX.toStringAsFixed(2)}, ${normY.toStringAsFixed(2)})',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pts[i] + const Offset(14, -22));
    }

    if (pts.length >= 2) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      if (pts.length == 4) path.close();
      canvas.drawPath(path, stroke);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 10.0;
    const gap = 7.0;
    final delta = b - a;
    final len = delta.distance;
    if (len <= 0) return;
    final dir = delta / len;
    var dist = 0.0;
    while (dist < len) {
      final start = a + dir * dist;
      final end = a + dir * (dist + dash).clamp(0.0, len);
      canvas.drawLine(start, end, paint..strokeWidth = 2);
      dist += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _CornerOverlayPainter oldDelegate) =>
      oldDelegate.corners != corners ||
      oldDelegate.renderSize != renderSize ||
      oldDelegate.guideCorners != guideCorners;
}

/// Full-screen corner picking with fit-width image and vertical scroll.
class _FullscreenCornerPicker extends StatefulWidget {
  const _FullscreenCornerPicker({
    required this.imageBytes,
    required this.imageSize,
    required this.cornerLabels,
    required this.guideCorners,
    required this.initialCorners,
    required this.onDone,
  });

  final Uint8List imageBytes;
  final Size imageSize;
  final List<String> cornerLabels;
  final List<Offset> guideCorners;
  final List<Offset> initialCorners;
  final void Function(List<Offset> corners) onDone;

  @override
  State<_FullscreenCornerPicker> createState() => _FullscreenCornerPickerState();
}

class _FullscreenCornerPickerState extends State<_FullscreenCornerPicker> {
  final ScrollController _scrollCtrl = ScrollController();
  late List<Offset> _corners;

  @override
  void initState() {
    super.initState();
    _corners = List<Offset>.from(widget.initialCorners);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  double _ySpan(List<Offset> corners) {
    if (corners.length != 4) return 0;
    final ys = corners.map((p) => p.dy / widget.imageSize.height);
    return ys.reduce((a, b) => a > b ? a : b) -
        ys.reduce((a, b) => a < b ? a : b);
  }

  void _scrollToNearEnd() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  void _addCorner(Offset local, Size renderSize) {
    if (_corners.length >= 4) return;
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx > renderSize.width ||
        local.dy > renderSize.height) {
      return;
    }
    setState(() {
      _corners.add(
        Offset(
          local.dx / renderSize.width * widget.imageSize.width,
          local.dy / renderSize.height * widget.imageSize.height,
        ),
      );
      if (_corners.length == 2) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNearEnd());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final scale = screenW / widget.imageSize.width;
    final renderH = widget.imageSize.height * scale;
    final renderSize = Size(screenW, renderH);

    final ySpan = _ySpan(_corners);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          _corners.length < 4
              ? widget.cornerLabels[_corners.length]
              : '4点完了 (y幅=${ySpan.toStringAsFixed(2)})',
        ),
        actions: [
          if (_corners.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _corners.removeLast()),
              child: const Text('1点戻す'),
            ),
          TextButton(
            onPressed: () => setState(_corners.clear),
            child: const Text('リセット'),
          ),
          FilledButton(
            onPressed: _corners.length == 4 && ySpan >= 0.35
                ? () {
                    widget.onDone(_corners);
                    Navigator.pop(context);
                  }
                : null,
            child: const Text('完了'),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: const Color(0xFFFFF8E1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                _corners.length < 2
                    ? '黄色の目安に合わせて ①② をタップ（画像の上の方）'
                    : _corners.length < 4
                        ? '③④ は BRUNSWICK 付近まで下にスクロールして黄色の目安へ'
                        : ySpan < 0.35
                            ? 'y幅が ${ySpan.toStringAsFixed(2)} と狭いです。手前の角をもっと下（y≈0.85）へ'
                            : 'OK — 完了を押してください',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _addCorner(d.localPosition, renderSize),
                child: SizedBox(
                  width: renderSize.width,
                  height: renderSize.height,
                  child: Stack(
                    children: [
                      Image.memory(
                        widget.imageBytes,
                        width: renderSize.width,
                        height: renderSize.height,
                        fit: BoxFit.fill,
                      ),
                      CustomPaint(
                        size: renderSize,
                        painter: _CornerOverlayPainter(
                          corners: _corners,
                          imageSize: widget.imageSize,
                          renderSize: renderSize,
                          guideCorners: widget.guideCorners,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
