import 'dart:async';

import '../entities/request_log.dart';

class LogFilter {
  final List<RequestMethod>? methods;
  final List<int>? statusCodes;
  final List<LogType>? logTypes;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? searchQuery;
  final String? profileId;

  const LogFilter({
    this.methods,
    this.statusCodes,
    this.logTypes,
    this.startDate,
    this.endDate,
    this.searchQuery,
    this.profileId,
  });

  LogFilter copyWith({
    List<RequestMethod>? methods,
    List<int>? statusCodes,
    List<LogType>? logTypes,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    String? profileId,
  }) {
    return LogFilter(
      methods: methods ?? this.methods,
      statusCodes: statusCodes ?? this.statusCodes,
      logTypes: logTypes ?? this.logTypes,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      searchQuery: searchQuery ?? this.searchQuery,
      profileId: profileId ?? this.profileId,
    );
  }
}

abstract class LogRepository {
  Future<List<RequestLog>> getAllLogs({LogFilter? filter});
  Future<RequestLog?> getLogById(String id);
  Future<void> createLog(RequestLog log);
  Future<void> clearLogs();
  Future<void> clearFilteredLogs(LogFilter filter);
  Future<String> exportLogs({LogFilter? filter});
  Stream<RequestLog> get newLogStream;
}