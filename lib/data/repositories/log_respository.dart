import 'dart:async';

import 'dart:convert';
import '../../domain/entities/request_log.dart';
import '../../domain/repositories/log_repository.dart';
import '../datasources/local/log_local_datasource.dart';
import '../models/request_log_model.dart';

class LogRepositoryImpl implements LogRepository {
  final LogLocalDataSource localDataSource;

  LogRepositoryImpl(this.localDataSource);

  @override
  Future<List<RequestLog>> getAllLogs({LogFilter? filter}) async {
    final models = await localDataSource.getAllLogs(filter: filter);
    return models.map((model) => model.toEntity()).toList();
  }

  @override
  Future<RequestLog?> getLogById(String id) async {
    final model = await localDataSource.getLogById(id);
    return model?.toEntity();
  }

  @override
  Future<void> createLog(RequestLog log) async {
    final model = RequestLogModel.fromEntity(log);
    await localDataSource.insertLog(model);
  }

  @override
  Future<void> clearLogs() async {
    await localDataSource.clearLogs();
  }

  @override
  Future<void> clearFilteredLogs(LogFilter filter) async {
    await localDataSource.clearFilteredLogs(filter);
  }

  @override
  Future<String> exportLogs({LogFilter? filter}) async {
    final models = await localDataSource.getAllLogs(filter: filter);
    final jsonList = models.map((model) => model.toJson()).toList();
    return jsonEncode({
      'version': '1.0',
      'exportDate': DateTime.now().toIso8601String(),
      'totalLogs': jsonList.length,
      'logs': jsonList,
    });
  }

  @override
  Stream<List<RequestLog>> watchLogs({LogFilter? filter}) {
    return localDataSource.watchLogs(filter: filter).map(
      (models) => models.map((model) => model.toEntity()).toList(),
    );
  }
}