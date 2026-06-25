import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readFilePathBytes(String path) async {
  return File(path).readAsBytes();
}
