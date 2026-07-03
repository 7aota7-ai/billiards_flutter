import 'dart:typed_data';

import 'photo_local_save_types.dart';

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
