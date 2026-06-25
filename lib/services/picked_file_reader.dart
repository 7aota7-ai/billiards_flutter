import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'picked_file_reader_io.dart'
    if (dart.library.html) 'picked_file_reader_web.dart' as path_reader;

Future<Uint8List?> readPlatformFileBytes(PlatformFile file) async {
  if (file.bytes != null) return file.bytes;
  if (kIsWeb || file.path == null) return null;
  return path_reader.readFilePathBytes(file.path!);
}
