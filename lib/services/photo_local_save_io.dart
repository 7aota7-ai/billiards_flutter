import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import 'photo_local_save_types.dart';

Future<PhotoSaveResult> saveImageToDevice(
  Uint8List bytes,
  String filename,
) async {
  try {
    await Gal.putImageBytes(bytes, name: filename);
    return const PhotoSaveResult(
      ok: true,
      target: PhotoSaveTarget.gallery,
      message: '写真アプリに保存しました',
    );
  } on GalException catch (e) {
    if (e.type == GalExceptionType.accessDenied) {
      return const PhotoSaveResult(
        ok: false,
        target: PhotoSaveTarget.none,
        message: '写真ライブラリへの保存が拒否されました（設定で許可してください）',
      );
    }
    return PhotoSaveResult.failed;
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
    await Share.shareXFiles([file], text: 'ビリヤード配置写真');
    return const PhotoSaveResult(
      ok: true,
      target: PhotoSaveTarget.gallery,
      message: '共有メニューを開きました',
    );
  } catch (_) {
    return PhotoSaveResult.failed;
  }
}
