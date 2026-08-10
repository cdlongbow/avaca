import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:avaca/controllers/data_transfer_controller.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/models/data_transfer_models.dart';
import 'package:avaca/services/data_transfer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePicker implements DataTransferPicker {
  Uint8List? importBytes;
  String? savedPath;
  Uint8List? savedBytes;
  String? savedFileName;

  @override
  Future<Uint8List?> pickImport() async => importBytes;

  @override
  Future<String?> saveExport({
    required Uint8List bytes,
    required String fileName,
  }) async {
    savedBytes = bytes;
    savedFileName = fileName;
    return savedPath;
  }
}

void main() {
  sqfliteFfiInit();

  late Directory directory;
  late AppDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'avaca_transfer_controller_',
    );
    database = AppDatabase.forTesting(
      baseDir: directory.path,
      databaseFactory: databaseFactoryFfi,
    );
    await database.init();
  });

  tearDown(() async {
    await database.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test('import cancellation leaves the controller idle', () async {
    final picker = _FakePicker();
    final controller = DataTransferController(
      service: DataTransferService(db: database),
      picker: picker,
    );

    final result = await controller.importData(resolveDuplicate: null);

    expect(result.cancelled, isTrue);
    expect(result.error, isNull);
    expect(controller.isBusy, isFalse);
    expect(controller.phase, DataTransferPhase.idle);
  });

  test('export saves a complete ZIP through the picker', () async {
    final picker = _FakePicker()..savedPath = 'C:\\Exports\\avaca.zip';
    final controller = DataTransferController(
      service: DataTransferService(db: database),
      picker: picker,
    );

    final result = await controller.exportData();

    expect(result.succeeded, isTrue);
    expect(result.summary?.destinationPath, picker.savedPath);
    expect(picker.savedFileName, endsWith('.zip'));
    expect(picker.savedBytes, isNotNull);
    expect(ZipDecoder().decodeBytes(picker.savedBytes!), isA<Archive>());
    expect(controller.isBusy, isFalse);
    expect(controller.phase, DataTransferPhase.success);
  });

  test('invalid import reports an error and releases the busy guard', () async {
    final picker = _FakePicker()..importBytes = Uint8List.fromList([1, 2, 3]);
    final controller = DataTransferController(
      service: DataTransferService(db: database),
      picker: picker,
    );

    final result = await controller.importData(resolveDuplicate: null);

    expect(result.succeeded, isFalse);
    expect(result.error, isNotNull);
    expect(controller.isBusy, isFalse);
    expect(controller.phase, DataTransferPhase.error);
  });
}
