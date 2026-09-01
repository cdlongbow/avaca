import 'library_filename_parser.dart';
import 'library_models.dart';

/// The authoritative, in-memory state for the Scan → Select → Review flow.
///
/// This object deliberately has no database or filesystem dependency.  It
/// owns the effective filename corrections and selection decisions so Review
/// and Commit cannot accidentally read stale widget-local state.
final class LibraryImportSession {
  LibraryImportSession({
    LibraryFilenameParser parser = const LibraryFilenameParser(),
  }) : _parser = parser;

  final LibraryFilenameParser _parser;
  List<LibraryScanEntry> _entries = const <LibraryScanEntry>[];
  String? _sourceFolder;
  String? _libraryRoot;
  int _revision = 0;

  List<LibraryScanEntry> get entries => List.unmodifiable(_entries);
  String? get sourceFolder => _sourceFolder;
  String? get libraryRoot => _libraryRoot;
  int get revision => _revision;

  int get selectedCount => _entries.where((entry) => entry.selected).length;

  List<LibraryScanEntry> get selectedEntries =>
      List.unmodifiable(_entries.where((entry) => entry.selected));

  void setSourceFolder(String? value) {
    final normalized = value?.trim();
    if (_sourceFolder ==
        (normalized == null || normalized.isEmpty ? null : normalized)) {
      return;
    }
    _sourceFolder = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    _entries = const <LibraryScanEntry>[];
    _bump();
  }

  void setLibraryRoot(String? value) {
    final normalized = value?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if (_libraryRoot == next) return;
    _libraryRoot = next;
    _bump();
  }

  void setEntries(Iterable<LibraryScanEntry> values) {
    _entries = List<LibraryScanEntry>.unmodifiable(
      values.map((entry) => entry.copyWith(selected: false)),
    );
    _bump();
  }

  void setSelected(int index, bool selected) {
    final entry = _entryAt(index);
    _replace(index, entry.copyWith(selected: selected));
  }

  void selectAllRecognizable() {
    _entries = List<LibraryScanEntry>.unmodifiable(
      _entries.map(
        (entry) => entry.parseResult.isImportable
            ? entry.copyWith(selected: true)
            : entry.copyWith(selected: false),
      ),
    );
    _bump();
  }

  void clearSelection() {
    _entries = List<LibraryScanEntry>.unmodifiable(
      _entries.map((entry) => entry.copyWith(selected: false)),
    );
    _bump();
  }

  /// Removes only entries whose physical source was successfully imported.
  ///
  /// Unresolved results stay visible for retry or repair, but none of the
  /// retained entries remains selected after a batch completes.
  void reconcileAfterImport(Iterable<String> succeededSourcePaths) {
    final succeeded = succeededSourcePaths.toSet();
    _entries = List<LibraryScanEntry>.unmodifiable(
      _entries
          .where((entry) => !succeeded.contains(entry.sourcePath))
          .map((entry) => entry.copyWith(selected: false)),
    );
    _bump();
  }

  void applyManualCode(int index, String value) {
    final entry = _entryAt(index);
    final parseResult = _parser.applyManualCode(entry.parseResult, value);
    _replace(
      index,
      entry.copyWith(
        parseResult: parseResult,
        selected: parseResult.isImportable ? entry.selected : false,
      ),
    );
  }

  LibraryScanEntry _entryAt(int index) {
    if (index < 0 || index >= _entries.length) {
      throw RangeError.index(index, _entries, 'index');
    }
    return _entries[index];
  }

  void _replace(int index, LibraryScanEntry value) {
    final next = [..._entries];
    next[index] = value;
    _entries = List<LibraryScanEntry>.unmodifiable(next);
    _bump();
  }

  void _bump() => _revision++;
}
