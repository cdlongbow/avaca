import 'package:flutter/foundation.dart';

import '../core/database.dart';

enum WorksLoadStatus { loading, loaded, notFound, error }

class WorksController extends ChangeNotifier {
  WorksController({required this.db, required this.actressId});

  final AppDatabase db;
  final int actressId;

  String actressName = '';
  WorksLoadStatus status = WorksLoadStatus.loading;
  Object? loadError;

  Future<void> init() async {
    try {
      final actress = await db.getActressById(actressId);

      if (actress == null) {
        status = WorksLoadStatus.notFound;
      } else {
        actressName = actress['name']?.toString() ?? '';
        status = WorksLoadStatus.loaded;
      }
    } catch (error) {
      loadError = error;
      status = WorksLoadStatus.error;
    }

    notifyListeners();
  }
}
