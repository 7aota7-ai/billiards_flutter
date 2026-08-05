import 'dart:typed_data';

import 'captured_photo_backup_store.dart';
import 'photo_local_save_types.dart';
import 'photo_local_save_platform.dart'
    if (dart.library.io) 'photo_local_save_io.dart'
    if (dart.library.js_interop) 'photo_local_save_web.dart';

/// 撮影・読込画像を端末へ保存し、アプリ内バックアップも更新する。
class PhotoLocalSaveService {
  PhotoLocalSaveService._();

  static String filenameFor({String? tag}) {
    final now = DateTime.now();
    final stamp =
        '${now.year}${_2(now.month)}${_2(now.day)}_${_2(now.hour)}${_2(now.minute)}${_2(now.second)}';
    final suffix = tag == null || tag.isEmpty ? '' : '_$tag';
    return 'billiards$stamp$suffix.jpg';
  }

  static String _2(int v) => v.toString().padLeft(2, '0');

  /// アプリ内バックアップのみ更新（端末への実保存はユーザー操作のボタンから行う）。
  ///
  /// 撮影直後にユーザー操作なしで端末ダウンロード/共有を自動発火すると、
  /// 表示中の Image.memory デコードとレースして失敗することがある
  /// （iOS Safari で確認: `EncodingError: Loading was canceled`）。
  /// 呼び出し元の表示用バッファを壊さないよう、常にコピーを保存する。
  static Future<PhotoSaveResult> saveCapture(
    Uint8List jpegBytes, {
    String? tag,
  }) async {
    final filename = filenameFor(tag: tag);
    final copy = Uint8List.fromList(jpegBytes);
    await CapturedPhotoBackupStore.save(copy, filename);
    return const PhotoSaveResult(
      ok: true,
      target: PhotoSaveTarget.none,
      message: 'アプリ内に一時保存しました（端末保存は「端末に保存」ボタンから）',
    );
  }

  /// 端末保存のみ（手動ボタン用）。
  static Future<PhotoSaveResult> saveToDevice(
    Uint8List jpegBytes, {
    String? filename,
  }) {
    return saveImageToDevice(
      jpegBytes,
      filename ?? filenameFor(tag: 'manual'),
    );
  }

  /// Web スマホ向け: 共有シートから写真アプリへ保存。
  static Future<PhotoSaveResult> shareToDevice(
    Uint8List jpegBytes, {
    String? filename,
  }) {
    return shareImageToDevice(
      jpegBytes,
      filename ?? filenameFor(tag: 'share'),
    );
  }
}
