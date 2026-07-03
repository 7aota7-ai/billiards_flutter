import 'dart:typed_data';

/// 端末の写真ライブラリ / ダウンロードフォルダへの保存結果。
enum PhotoSaveTarget { gallery, downloads, none }

class PhotoSaveResult {
  const PhotoSaveResult({
    required this.ok,
    required this.target,
    required this.message,
  });

  final bool ok;
  final PhotoSaveTarget target;
  final String message;

  static const failed = PhotoSaveResult(
    ok: false,
    target: PhotoSaveTarget.none,
    message: '写真を端末に保存できませんでした',
  );
}

Future<PhotoSaveResult> saveImageToDevice(
  Uint8List bytes,
  String filename,
) async {
  throw UnsupportedError('saveImageToDevice is not implemented on this platform');
}

Future<PhotoSaveResult> shareImageToDevice(
  Uint8List bytes,
  String filename,
) async {
  throw UnsupportedError('shareImageToDevice is not implemented on this platform');
}
