import 'package:flutter_test/flutter_test.dart';

import 'package:avaca/library/library_filename_parser.dart';
import 'package:avaca/library/library_models.dart';

void main() {
  const parser = LibraryFilenameParser();

  test('normalizes compact codes and preserves RUC semantics', () {
    final result = parser.parse('[FHD] SSIS00123-RUC.mp4');

    expect(result.status, LibraryParseStatus.recognized);
    expect(result.code, 'SSIS-123');
    expect(result.normalizedCode, 'SSIS-123');
    expect(result.variantToken, 'RUC');
    expect(result.variantType, 'leak');
    expect(result.hasChineseSubtitles, isTrue);
    expect(result.noiseTokens, contains('FHD'));
  });

  test('normalizes compact and hyphenated zero-padded codes identically', () {
    for (final fileName in <String>[
      'ssis00123_4k60_UC.mp4',
      'SSIS00123_UC.mkv',
      'SSIS00123_4K_U.mp4',
      'SSIS00123_1080P_C.mp4',
      'SSIS00123_4K60_RU.mp4',
      'SSIS00123 4K60 UC.mp4',
      'SSIS00123.UC.mp4',
      'SSIS-00123_4K60_UC.mp4',
      '[FHD] SSIS00123-RUC.mp4',
    ]) {
      final result = parser.parse(fileName);
      expect(result.normalizedCode, 'SSIS-123', reason: fileName);
    }
    expect(parser.parse('ssis00123_4k60_UC.mp4').variantToken, 'UC');
    expect(parser.parse('SSIS00123_4K_U.mp4').variantToken, 'U');
    expect(parser.parse('SSIS00123_1080P_C.mp4').variantToken, 'C');
    expect(parser.parse('SSIS00123_4K60_RU.mp4').variantToken, 'RU');
    expect(parser.parse('SSIS00123 4K60 UC.mp4').variantToken, 'UC');
    expect(parser.parse('SSIS00123.UC.mp4').variantToken, 'UC');
  });

  test(
    'accepts underscore and dot separators without accepting substrings',
    () {
      expect(parser.parse('prefix_SSIS00123_suffix.mp4').isImportable, isTrue);
      expect(parser.parse('prefix.SSIS00123.suffix.mp4').isImportable, isTrue);
      expect(parser.parse('somethingUhere.mp4').isImportable, isFalse);
      expect(parser.parse('SSIS00123_UCextra.mp4').variantToken, isNull);
    },
  );

  test('uses exact longest-match variant tokens', () {
    final cases = <String, LibraryVariant>{
      'ABC-123-U.mp4': LibraryVariant.u,
      'ABC-123-C.mp4': LibraryVariant.c,
      'ABC-123-UC.mp4': LibraryVariant.uc,
      'ABC-123-RU.mp4': LibraryVariant.ru,
      'ABC-123-RUC.mp4': LibraryVariant.ruc,
    };
    for (final entry in cases.entries) {
      final result = parser.parse(entry.key);
      expect(result.variantToken, entry.value.token, reason: entry.key);
      expect(result.variantType, entry.value.type, reason: entry.key);
      expect(
        result.hasChineseSubtitles,
        entry.value.hasChineseSubtitles,
        reason: entry.key,
      );
    }
  });

  test('keeps multipart filenames distinct', () {
    final first = parser.parse('SSIS-123-RUC-CD1.mp4');
    final second = parser.parse('SSIS-123-RUC-CD2.mp4');

    expect(first.partNumber, 1);
    expect(second.partNumber, 2);
    expect(first.normalizedCode, second.normalizedCode);
  });

  test('rejects ambiguous or unsupported filename input', () {
    expect(
      parser.parse('SSIS-123 ABC-456.mp4').status,
      LibraryParseStatus.ambiguous,
    );
    expect(parser.parse('unknown.txt').status, LibraryParseStatus.unrecognized);
    expect(parser.parse('somethingUhere.mp4').isImportable, isFalse);
  });

  test('manual correction still uses the conservative grammar', () {
    final original = parser.parse('download.mp4');
    final corrected = parser.applyManualCode(original, 'SSIS-123');
    final rejected = parser.applyManualCode(original, 'SSIS');

    expect(corrected.isImportable, isTrue);
    expect(corrected.normalizedCode, 'SSIS-123');
    expect(rejected.isImportable, isFalse);
  });

  test(
    'manual correction accepts compact input and stores its canonical code',
    () {
      final original = parser.parse('download.mp4');
      final corrected = parser.applyManualCode(original, 'ssis00123');

      expect(corrected.isImportable, isTrue);
      expect(corrected.code, 'SSIS-123');
      expect(corrected.normalizedCode, 'SSIS-123');
    },
  );
}
