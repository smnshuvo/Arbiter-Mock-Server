import '../entities/request_log.dart';

class LogFilter {
  final List<RequestMethod>? methods;
  final List<int>? statusCodes;
  final List<LogType>? logTypes;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? searchQuery;

  const LogFilter({
    this.methods,
    this.statusCodes,
    this.logTypes,
    this.startDate,
    this.endDate,
    this.searchQuery,
  });
}

abstract class LogRepository {
  Future<List<RequestLog>> getAllLogs({LogFilter? filter});
  Future<RequestLog?> getLogById(String id);
  Future<void> createLog(RequestLog log);
  Future<void> clearLogs();
  Future<void> clearFilteredLogs(LogFilter filter);
  Future<String> exportLogs({LogFilter? filter});
}