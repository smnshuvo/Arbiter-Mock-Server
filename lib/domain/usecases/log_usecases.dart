import 'dart:async';

import '../entities/request_log.dart';
import '../repositories/log_repository.dart';

class GetAllLogs {
  final LogRepository repository;

  GetAllLogs(this.repository);

  Future<List<RequestLog>> call({LogFilter? filter}) async {
    return await repository.getAllLogs(filter: filter);
  }
}

class CreateLog {
  final LogRepository repository;

  CreateLog(this.repository);

  Future<void> call(RequestLog log) async {
    await repository.createLog(log);
  }
}

class ClearLogs {
  final LogRepository repository;

  ClearLogs(this.repository);

  Future<void> call() async {
    await repository.clearLogs();
  }
}

class ClearFilteredLogs {
  final LogRepository repository;

  ClearFilteredLogs(this.repository);

  Future<void> call(LogFilter filter) async {
    await repository.clearFilteredLogs(filter);
  }
}

class ExportLogs {
  final LogRepository repository;

  ExportLogs(this.repository);

  Future<String> call({LogFilter? filter}) async {
    return await repository.exportLogs(filter: filter);
  }
}

class WatchLogs {
  final LogRepository repository;

  WatchLogs(this.repository);

  Stream<List<RequestLog>> call({LogFilter? filter}) {
    return repository.watchLogs(filter: filter);
  }
}