import 'dart:typed_data';
import 'dart:ui';

import '../models/detected_ball_layout.dart';

/// 写真読込 → 配置エディタへ検出結果と参照写真を渡すための一時ストア（メモリのみ）。
class PendingPhotoImport {
  const PendingPhotoImport({
    required this.layout,
    this.imageBytes,
    this.imageSize,
    this.cornersNormalized,
  });

  final DetectedBallLayout layout;
  final Uint8List? imageBytes;
  final Size? imageSize;
  final List<List<double>>? cornersNormalized;
}

class PendingPhotoImportStore {
  PendingPhotoImportStore._();

  static PendingPhotoImport? _pending;

  static void set(PendingPhotoImport payload) {
    _pending = payload;
  }

  /// 取り出したらクリアする。
  static PendingPhotoImport? take() {
    final value = _pending;
    _pending = null;
    return value;
  }
}
