import 'dart:typed_data';

import 'package:billiards_flutter/services/captured_photo_backup_store.dart';
import 'package:billiards_flutter/services/photo_local_save_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('filenameFor includes billiards prefix and jpg suffix', () {
    final name = PhotoLocalSaveService.filenameFor(tag: 'capture');
    expect(name.startsWith('billiards'), isTrue);
    expect(name.endsWith('_capture.jpg'), isTrue);
  });

  test('CapturedPhotoBackupStore round-trip', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    await CapturedPhotoBackupStore.save(bytes, 'test.jpg');
    final loaded = await CapturedPhotoBackupStore.load();
    expect(loaded, isNotNull);
    expect(loaded!.filename, 'test.jpg');
    expect(loaded.bytes, bytes);
  });

  test('saveCapture keeps caller buffer intact for Image.memory', () async {
    final original = Uint8List.fromList(List<int>.generate(64, (i) => i));
    final before = List<int>.from(original);
    // Device save may fail in unit tests; backup path must not clear [original].
    await PhotoLocalSaveService.saveCapture(original, tag: 'unit');
    expect(original, before);
    expect(original.length, 64);
  });
}
