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
