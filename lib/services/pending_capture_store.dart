import 'dart:typed_data';
import 'dart:ui';

/// Camera capture handed off to photo-import when API is unavailable.
class PendingCaptureStore {
  PendingCaptureStore._();

  static PendingCapture? _pending;

  static void set({
    required Uint8List bytes,
    required Size imageSize,
    List<List<double>>? cornersNormalized,
  }) {
    _pending = PendingCapture(
      bytes: bytes,
      imageSize: imageSize,
      cornersNormalized: cornersNormalized,
    );
  }

  static PendingCapture? take() {
    final v = _pending;
    _pending = null;
    return v;
  }
}

class PendingCapture {
  const PendingCapture({
    required this.bytes,
    required this.imageSize,
    this.cornersNormalized,
  });

  final Uint8List bytes;
  final Size imageSize;
  final List<List<double>>? cornersNormalized;
}
