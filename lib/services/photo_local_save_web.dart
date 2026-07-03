import 'dart:js_interop';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';
import 'package:web/web.dart' as web;

import 'photo_local_save_types.dart';

Future<PhotoSaveResult> saveImageToDevice(
  Uint8List bytes,
  String filename,
) async {
  try {
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/jpeg'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = filename;
    anchor.click();
    web.URL.revokeObjectURL(url);
    return const PhotoSaveResult(
      ok: true,
      target: PhotoSaveTarget.downloads,
      message: 'ダウンロードに保存しました（スマホ: ファイル→ダウンロード）',
    );
  } catch (_) {
    return PhotoSaveResult.failed;
  }
}

Future<PhotoSaveResult> shareImageToDevice(
  Uint8List bytes,
  String filename,
) async {
  try {
    final file = XFile.fromData(
      bytes,
      mimeType: 'image/jpeg',
      name: filename,
    );
    await Share.shareXFiles(
      [file],
      text: 'ビリヤード配置写真',
    );
    return const PhotoSaveResult(
      ok: true,
      target: PhotoSaveTarget.gallery,
      message: '共有メニューから「写真に保存」を選べます',
    );
  } catch (_) {
    return PhotoSaveResult.failed;
  }
}
