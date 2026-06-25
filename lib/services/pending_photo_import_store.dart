import '../models/detected_ball_layout.dart';

/// 写真読込 → 配置エディタへ検出結果を渡すための一時ストア（メモリのみ）。
class PendingPhotoImportStore {
  PendingPhotoImportStore._();

  static DetectedBallLayout? _pending;

  static void set(DetectedBallLayout layout) {
    _pending = layout;
  }

  /// 取り出したらクリアする。
  static DetectedBallLayout? take() {
    final value = _pending;
    _pending = null;
    return value;
  }
}
