import 'dart:async';
import 'dart:convert';
import '../../domain/entities/request_log.dart';
import '../../domain/repositories/log_repository.dart';
import '../datasources/local/log_local_datasource.dart';
import '../models/request_log_model.dart';

class LogRepositoryImpl implements LogRepository {
  final LogLocalDataSource localDataSource;
  final StreamController<RequestLog> _logStreamController;

  LogRepositoryImpl(this.localDataSource)
      : _logStreamController = StreamController<RequestLog>.broadcast();

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

    // Emit the log to the stream for real-time updates
    _logStreamController.add(log);
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
  Stream<RequestLog> watchRecentLogs() {
    return _logStreamController.stream;
  }

  @override
  Future<List<RequestLog>> getRecentLogs({int limit = 3}) async {
    final models = await localDataSource.getAllLogs();
    final logs = models.map((model) => model.toEntity()).toList();

    // Return the last N logs
    if (logs.length <= limit) {
      return logs;
    }
    return logs.sublist(logs.length - limit);
  }

  void dispose() {
    _logStreamController.close();
  }
}