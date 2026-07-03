import 'package:billiards_flutter/services/captured_photo_backup_store.dart';
import 'package:billiards_flutter/services/photo_local_save_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filenameFor includes billiards prefix and jpg suffix', () {
    final name = PhotoLocalSaveService.filenameFor(tag: 'capture');
    expect(name.startsWith('billiards'), isTrue);
    expect(name.endsWith('_capture.jpg'), isTrue);
  });

  test('CapturedPhotoBackupStore round-trip', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = [1, 2, 3, 4, 5];
    await CapturedPhotoBackupStore.save(bytes, 'test.jpg');
    final loaded = await CapturedPhotoBackupStore.load();
    expect(loaded, isNotNull);
    expect(loaded!.filename, 'test.jpg');
    expect(loaded.bytes, bytes);
  });
}
