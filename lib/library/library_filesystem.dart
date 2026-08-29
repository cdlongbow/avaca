import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import 'library_filename_parser.dart';
import 'library_models.dart';

class LibraryFilesystemException implements Exception {
  const LibraryFilesystemException(this.message, {this.pathValue});

  final String message;
  final String? pathValue;

  @override
  String toString() => pathValue == null
      ? 'LibraryFilesystemException: $message'
      : 'LibraryFilesystemException: $message ($pathValue)';
}

class LibraryShortcutException implements Exception {
  const LibraryShortcutException(this.message);

  final String message;

  @override
  String toString() => 'LibraryShortcutException: $message';
}

class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get value {
    final digest = _digest;
    if (digest == null) {
      throw StateError('digest was not closed');
    }
    return digest;
  }

  @override
  void add(Digest value) => _digest = value;

  @override
  void close() {}
}

/// Safe filesystem operations used by the folder import journal.
///
/// The class accepts an optional clock and stat override so the destructive
/// import state machine can be tested without touching a real library.
class LibraryFilesystem {
  LibraryFilesystem({
    DateTime Function()? clock,
    Future<LibraryFileSnapshot> Function(String path)? snapshotOverride,
  }) : _clock = clock ?? DateTime.now,
       _snapshotOverride = snapshotOverride;

  final DateTime Function() _clock;
  final Future<LibraryFileSnapshot> Function(String path)? _snapshotOverride;

  String absolutePath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const LibraryFilesystemException('path cannot be empty');
    }
    return path.normalize(File(trimmed).absolute.path);
  }

  bool isWithin(String root, String candidate, {bool allowRoot = false}) {
    final normalizedRoot = absolutePath(root);
    final normalizedCandidate = absolutePath(candidate);
    if (samePath(normalizedRoot, normalizedCandidate)) return allowRoot;
    final relative = path.relative(normalizedCandidate, from: normalizedRoot);
    return relative != '..' &&
        !relative.startsWith('..${path.separator}') &&
        !path.isAbsolute(relative);
  }

  bool samePath(String left, String right) {
    final normalizedLeft = absolutePath(left).replaceAll('/', '\\');
    final normalizedRight = absolutePath(right).replaceAll('/', '\\');
    return Platform.isWindows
        ? normalizedLeft.toLowerCase() == normalizedRight.toLowerCase()
        : normalizedLeft == normalizedRight;
  }

  void validateRoot(String root) {
    final normalized = absolutePath(root);
    if (!path.isAbsolute(normalized)) {
      throw LibraryFilesystemException(
        'root must be absolute',
        pathValue: root,
      );
    }
    if (normalized == path.dirname(normalized) &&
        !Platform.isWindows &&
        normalized == '/') {
      throw const LibraryFilesystemException(
        'filesystem root is not a library root',
      );
    }
  }

  String validateRelativePath(String relative) {
    final normalizedSeparators = relative.trim().replaceAll('\\', '/');
    if (normalizedSeparators.isEmpty ||
        normalizedSeparators.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalizedSeparators)) {
      throw LibraryFilesystemException(
        'relative path must not be absolute',
        pathValue: relative,
      );
    }
    final segments = normalizedSeparators.split('/');
    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw LibraryFilesystemException(
        'relative path contains an unsafe segment',
        pathValue: relative,
      );
    }
    for (final segment in segments) {
      _validateSegment(segment);
    }
    return segments.join('/');
  }

  String safeSegment(String value, {String fallback = '_'}) {
    var result = value.trim().replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    result = result.replaceAll(RegExp(r'[. ]+$'), '');
    if (result.isEmpty) result = fallback;
    final upper = result.toUpperCase();
    if (_reservedNames.contains(upper)) result = '_$result';
    _validateSegment(result);
    return result;
  }

  Future<LibraryFileSnapshot> snapshot(String filePath) async {
    final override = _snapshotOverride;
    if (override != null) return override(filePath);
    final normalized = absolutePath(filePath);
    final entityType = await FileSystemEntity.type(
      normalized,
      followLinks: false,
    );
    if (entityType == FileSystemEntityType.link) {
      throw LibraryFilesystemException(
        'symbolic links are not valid media inputs',
        pathValue: normalized,
      );
    }
    final file = File(normalized);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw LibraryFilesystemException(
        'expected a regular file',
        pathValue: normalized,
      );
    }
    return LibraryFileSnapshot(
      path: normalized,
      sizeBytes: stat.size,
      modifiedAt: stat.modified,
      createdAt: await _windowsCreationTime(normalized) ?? stat.changed,
      changedAt: stat.changed,
    );
  }

  /// Rejects symbolic links in the portion of [candidate] controlled by a
  /// library root.  Shortcut files are ordinary files on Windows and are
  /// handled separately by the scanner/link manager.
  Future<void> validateNoSymbolicLinks(String root, String candidate) async {
    final normalizedRoot = absolutePath(root);
    final normalizedCandidate = absolutePath(candidate);
    if (!isWithin(normalizedRoot, normalizedCandidate, allowRoot: true)) {
      throw LibraryFilesystemException(
        'candidate is outside the supplied root',
        pathValue: normalizedCandidate,
      );
    }
    final rootType = await FileSystemEntity.type(
      normalizedRoot,
      followLinks: false,
    );
    if (rootType == FileSystemEntityType.link) {
      throw LibraryFilesystemException(
        'symbolic-link roots are not supported',
        pathValue: normalizedRoot,
      );
    }
    final relative = path.relative(normalizedCandidate, from: normalizedRoot);
    if (relative.isEmpty || relative == '.') return;
    var current = normalizedRoot;
    for (final segment in relative.split(path.separator)) {
      if (segment.isEmpty || segment == '.') continue;
      current = path.join(current, segment);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw LibraryFilesystemException(
          'symbolic links are not valid inside the library path',
          pathValue: current,
        );
      }
    }
  }

  Future<String> hashFile(String filePath) async {
    final digestSink = _DigestSink();
    final digestInput = sha256.startChunkedConversion(digestSink);
    try {
      await for (final chunk in File(absolutePath(filePath)).openRead()) {
        digestInput.add(chunk);
      }
    } finally {
      digestInput.close();
    }
    return digestSink.value.toString();
  }

  Future<String> copyAndHash(
    String sourcePath,
    String destinationPath, {
    LibraryFileSnapshot? expectedSnapshot,
    void Function(int bytes)? onBytes,
  }) async {
    final source = absolutePath(sourcePath);
    final destination = absolutePath(destinationPath);
    final before = await snapshot(source);
    if (expectedSnapshot != null && !before.matches(expectedSnapshot)) {
      throw const LibraryFilesystemException('source changed before copying');
    }
    await Directory(path.dirname(destination)).create(recursive: true);
    final digestSink = _DigestSink();
    final digestInput = sha256.startChunkedConversion(digestSink);
    final output = File(destination).openWrite();
    var bytesWritten = 0;
    try {
      await for (final chunk in File(source).openRead()) {
        bytesWritten += chunk.length;
        digestInput.add(chunk);
        output.add(chunk);
        onBytes?.call(bytesWritten);
      }
    } finally {
      digestInput.close();
      await output.flush();
      await output.close();
    }
    final after = await snapshot(source);
    if (!before.matches(after) || bytesWritten != after.sizeBytes) {
      throw const LibraryFilesystemException('source changed while copying');
    }
    final destinationSnapshot = await snapshot(destination);
    if (destinationSnapshot.sizeBytes != bytesWritten) {
      throw const LibraryFilesystemException(
        'destination size verification failed',
      );
    }
    return digestSink.value.toString();
  }

  Future<void> writeJsonAtomically(
    String targetPath,
    Map<String, Object?> document,
  ) async {
    final target = absolutePath(targetPath);
    final parent = Directory(path.dirname(target));
    await parent.create(recursive: true);
    final temporary = File(
      path.join(
        parent.path,
        '.__avaca_${path.basename(target)}.${_clock().microsecondsSinceEpoch}.tmp',
      ),
    );
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document),
      flush: true,
    );
    final backup = File('$target.bak');
    try {
      if (await backup.exists()) await backup.delete();
      if (await File(target).exists()) await File(target).rename(backup.path);
      await temporary.rename(target);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await File(target).exists() && await backup.exists()) {
        await backup.rename(target);
      }
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> deleteFileIfExists(String filePath) async {
    final file = File(absolutePath(filePath));
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteStagingTree(
    String stagingPath, {
    required String stagingRoot,
  }) async {
    final normalized = absolutePath(stagingPath);
    if (!isWithin(stagingRoot, normalized, allowRoot: false)) {
      throw LibraryFilesystemException(
        'refusing to delete a path outside the staging root',
        pathValue: normalized,
      );
    }
    final directory = Directory(normalized);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  void _validateSegment(String segment) {
    if (segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.contains(RegExp(r'[<>:"/\\|?*\x00-\x1F]')) ||
        segment.endsWith('.') ||
        segment.endsWith(' ')) {
      throw LibraryFilesystemException(
        'unsafe path segment',
        pathValue: segment,
      );
    }
    if (_reservedNames.contains(segment.toUpperCase())) {
      throw LibraryFilesystemException(
        'reserved Windows path segment',
        pathValue: segment,
      );
    }
  }

  Future<DateTime?> _windowsCreationTime(String filePath) async {
    if (!Platform.isWindows) return null;
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getFileAttributesEx = kernel32
        .lookupFunction<_GetFileAttributesExNative, _GetFileAttributesExDart>(
          'GetFileAttributesExW',
        );
    final nativePath = filePath.toNativeUtf16();
    final data = calloc<_Win32FileAttributeData>();
    try {
      if (getFileAttributesEx(nativePath, 0, data) == 0) return null;
      final fileTime = (data.ref.creationHigh << 32) | data.ref.creationLow;
      if (fileTime <= 0) return null;
      const windowsEpochOffset = 116444736000000000;
      final milliseconds = (fileTime - windowsEpochOffset) ~/ 10000;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    } finally {
      calloc.free(data);
      calloc.free(nativePath);
    }
  }

  static const Set<String> _reservedNames = <String>{
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };
}

abstract interface class LibraryShortcutManager {
  bool get isSupported;

  Future<void> createDirectoryShortcut({
    required String linkPath,
    required String targetPath,
  });
}

class WindowsShortcutManager implements LibraryShortcutManager {
  const WindowsShortcutManager();

  @override
  bool get isSupported => Platform.isWindows;

  @override
  Future<void> createDirectoryShortcut({
    required String linkPath,
    required String targetPath,
  }) async {
    if (!Platform.isWindows) {
      throw const LibraryShortcutException(
        'Windows shortcuts are unavailable on this platform',
      );
    }
    final link = File(linkPath);
    await link.parent.create(recursive: true);
    final escapedLink = _powershellLiteral(File(linkPath).absolute.path);
    final escapedTarget = _powershellLiteral(
      Directory(targetPath).absolute.path,
    );
    final escapedWorkingDirectory = _powershellLiteral(
      Directory(targetPath).parent.absolute.path,
    );
    final script =
        "\$shell = New-Object -ComObject WScript.Shell; "
        "\$shortcut = \$shell.CreateShortcut($escapedLink); "
        "\$shortcut.TargetPath = $escapedTarget; "
        "\$shortcut.WorkingDirectory = $escapedWorkingDirectory; "
        "\$shortcut.Save()";
    final result = await Process.run('powershell.exe', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ], runInShell: false);
    if (result.exitCode != 0 || !await link.exists()) {
      throw LibraryShortcutException(
        'could not create .lnk: ${result.stderr}'.trim(),
      );
    }
  }

  String _powershellLiteral(String value) => "'${value.replaceAll("'", "''")}'";
}

class NoopShortcutManager implements LibraryShortcutManager {
  const NoopShortcutManager();

  @override
  bool get isSupported => false;

  @override
  Future<void> createDirectoryShortcut({
    required String linkPath,
    required String targetPath,
  }) async {}
}

/// A recursive phase-1 scanner.  It only reads directory entries and file
/// metadata; it never creates folders, downloads metadata, or changes a
/// source file.
class LibraryFolderScanner {
  LibraryFolderScanner({
    LibraryFilenameParser parser = const LibraryFilenameParser(),
    LibraryFilesystem? filesystem,
  }) : _parser = parser,
       _filesystem = filesystem ?? LibraryFilesystem();

  final LibraryFilenameParser _parser;
  final LibraryFilesystem _filesystem;

  Future<List<LibraryScanEntry>> scan(String folderPath) async {
    final folder = _filesystem.absolutePath(folderPath);
    _filesystem.validateRoot(folder);
    await _filesystem.validateNoSymbolicLinks(folder, folder);
    final directory = Directory(folder);
    if (!await directory.exists()) {
      throw LibraryFilesystemException(
        'source folder does not exist',
        pathValue: folder,
      );
    }
    final entries = <LibraryScanEntry>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File ||
          _isIgnored(entity.path) ||
          await FileSystemEntity.type(entity.path, followLinks: false) ==
              FileSystemEntityType.link) {
        continue;
      }
      final snapshot = await _filesystem.snapshot(entity.path);
      final fileName = path.basename(entity.path);
      entries.add(
        LibraryScanEntry(
          sourcePath: _filesystem.absolutePath(entity.path),
          originalFileName: fileName,
          sizeBytes: snapshot.sizeBytes,
          modifiedAt: snapshot.modifiedAt,
          createdAt: snapshot.createdAt,
          parseResult: _parser.parse(fileName),
        ),
      );
    }
    entries.sort(
      (left, right) => left.sourcePath.toLowerCase().compareTo(
        right.sourcePath.toLowerCase(),
      ),
    );
    return List.unmodifiable(entries);
  }

  bool _isIgnored(String value) {
    final lower = path.basename(value).toLowerCase();
    return lower.endsWith('.lnk') ||
        lower.endsWith('.url') ||
        lower.endsWith('.avaca-link') ||
        lower.endsWith('.tmp') ||
        lower.startsWith('.__avaca_');
  }
}

typedef _GetFileAttributesExNative =
    Int32 Function(Pointer<Utf16>, Uint32, Pointer<_Win32FileAttributeData>);
typedef _GetFileAttributesExDart =
    int Function(Pointer<Utf16>, int, Pointer<_Win32FileAttributeData>);

final class _Win32FileAttributeData extends Struct {
  @Uint32()
  external int attributes;
  @Uint32()
  external int creationLow;
  @Uint32()
  external int creationHigh;
  @Uint32()
  external int accessLow;
  @Uint32()
  external int accessHigh;
  @Uint32()
  external int writeLow;
  @Uint32()
  external int writeHigh;
  @Uint32()
  external int sizeHigh;
  @Uint32()
  external int sizeLow;
}
