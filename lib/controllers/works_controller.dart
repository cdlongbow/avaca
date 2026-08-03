import 'package:flutter/foundation.dart';

import '../core/database.dart';

enum WorksLoadStatus { loading, loaded, notFound, error }

class WorksController extends ChangeNotifier {
  WorksController({required this.db, required this.actressId});

  final AppDatabase db;
  final int actressId;

  String actressName = '';
  List<String> actressAliases = const [];
  List<Map<String, Object?>> works = const [];
  WorksLoadStatus status = WorksLoadStatus.loading;
  Object? loadError;

  Future<void> init() async {
    try {
      final actress = await db.getActressById(actressId);

      if (actress == null) {
        status = WorksLoadStatus.notFound;
      } else {
        actressName = actress['name']?.toString() ?? '';
        final aliases = actress['aliases'];
        actressAliases = aliases is Iterable
            ? aliases.map((alias) => alias.toString()).toList(growable: false)
            : const [];
        works = await db.getWorksForActress(actressId);
        status = WorksLoadStatus.loaded;
      }
    } catch (error) {
      loadError = error;
      status = WorksLoadStatus.error;
    }

    notifyListeners();
  }

  Future<void> reloadWorks() async {
    works = await db.getWorksForActress(actressId);
    notifyListeners();
  }
}
