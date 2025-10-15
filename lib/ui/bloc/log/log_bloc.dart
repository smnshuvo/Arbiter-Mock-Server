import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/request_log.dart';
import '../../../domain/repositories/log_repository.dart';
import '../../../domain/usecases/log_usecases.dart';

// Events
abstract class LogEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadLogsEvent extends LogEvent {
  final LogFilter? filter;
  LoadLogsEvent({this.filter});

  @override
  List<Object?> get props => [filter];
}

class LoadRecentLogsEvent extends LogEvent {}

class WatchRealtimeLogsEvent extends LogEvent {}

class NewLogReceivedEvent extends LogEvent {
  final RequestLog log;
  NewLogReceivedEvent(this.log);

  @override
  List<Object?> get props => [log];
}

class ClearLogsEvent extends LogEvent {}

class ClearFilteredLogsEvent extends LogEvent {
  final LogFilter filter;
  ClearFilteredLogsEvent(this.filter);

  @override
  List<Object?> get props => [filter];
}

class ExportLogsEvent extends LogEvent {
  final LogFilter? filter;
  ExportLogsEvent({this.filter});

  @override
  List<Object?> get props => [filter];
}

class ApplyFilterEvent extends LogEvent {
  final LogFilter filter;
  ApplyFilterEvent(this.filter);

  @override
  List<Object?> get props => [filter];
}

// States
abstract class LogState extends Equatable {
  @override
  List<Object?> get props => [];
}

class LogInitial extends LogState {}

class LogLoading extends LogState {}

class LogLoaded extends LogState {
  final List<RequestLog> logs;
  final LogFilter? currentFilter;

  LogLoaded(this.logs, {this.currentFilter});

  @override
  List<Object?> get props => [logs, currentFilter];
}

class RecentLogsLoaded extends LogState {
  final List<RequestLog> logs;

  RecentLogsLoaded(this.logs);

  @override
  List<Object?> get props => [logs];
}

class LogExported extends LogState {
  final String jsonData;

  LogExported(this.jsonData);

  @override
  List<Object?> get props => [jsonData];
}

class LogError extends LogState {
  final String message;

  LogError(this.message);

  @override
  List<Object?> get props => [message];
}

// BLoC
class LogBloc extends Bloc<LogEvent, LogState> {
  final GetAllLogs getAllLogs;
  final ClearLogs clearLogs;
  final ClearFilteredLogs clearFilteredLogs;
  final ExportLogs exportLogs;
  final LogRepository logRepository;

  StreamSubscription? _logStreamSubscription;

  LogBloc({
    required this.getAllLogs,
    required this.clearLogs,
    required this.clearFilteredLogs,
    required this.exportLogs,
    required this.logRepository,
  }) : super(LogInitial()) {
    on<LoadLogsEvent>(_onLoadLogs);
    on<LoadRecentLogsEvent>(_onLoadRecentLogs);
    on<WatchRealtimeLogsEvent>(_onWatchRealtimeLogs);
    on<NewLogReceivedEvent>(_onNewLogReceived);
    on<ClearLogsEvent>(_onClearLogs);
    on<ClearFilteredLogsEvent>(_onClearFilteredLogs);
    on<ExportLogsEvent>(_onExportLogs);
    on<ApplyFilterEvent>(_onApplyFilter);
  }

  Future<void> _onLoadLogs(
      LoadLogsEvent event,
      Emitter<LogState> emit,
      ) async {
    emit(LogLoading());
    try {
      final logs = await getAllLogs(filter: event.filter);
      emit(LogLoaded(logs, currentFilter: event.filter));
    } catch (e) {
      emit(LogError(e.toString()));
    }
  }

  Future<void> _onLoadRecentLogs(
      LoadRecentLogsEvent event,
      Emitter<LogState> emit,
      ) async {
    try {
      final logs = await logRepository.getRecentLogs(limit: 3);
      emit(RecentLogsLoaded(logs));
    } catch (e) {
      emit(LogError(e.toString()));
    }
  }

  Future<void> _onWatchRealtimeLogs(
      WatchRealtimeLogsEvent event,
      Emitter<LogState> emit,
      ) async {
    // Cancel existing subscription if any
    await _logStreamSubscription?.cancel();

    // Load initial recent logs
    try {
      final logs = await logRepository.getRecentLogs(limit: 3);
      emit(RecentLogsLoaded(logs));
    } catch (e) {
      emit(LogError(e.toString()));
      return;
    }

    // Listen to new logs
    _logStreamSubscription = logRepository.watchRecentLogs().listen(
          (newLog) {
        add(NewLogReceivedEvent(newLog));
      },
    );
  }

  Future<void> _onNewLogReceived(
      NewLogReceivedEvent event,
      Emitter<LogState> emit,
      ) async {
    try {
      final logs = await logRepository.getRecentLogs(limit: 3);
      emit(RecentLogsLoaded(logs));
    } catch (e) {
      emit(LogError(e.toString()));
    }
  }

  Future<void> _onClearLogs(
      ClearLogsEvent event,
      Emitter<LogState> emit,
      ) async {
    try {
      await clearLogs();
      emit(LogLoaded([]));
    } catch (e) {
      emit(LogError(e.toString()));
    }
  }

  Future<void> _onClearFilteredLogs(
      ClearFilteredLogsEvent event,
      Emitter<LogState> emit,
      ) async {
    try {
      await clearFilteredLogs(event.filter);
      final logs = await getAllLogs(filter: event.filter);
      emit(LogLoaded(logs, currentFilter: event.filter));
    } catch (e) {
      emit(LogError(e.toString()));
    }
  }

  Future<void> _onExportLogs(
      ExportLogsEvent event,
      Emitter<LogState> emit,
      ) async {
    try {
      final jsonData = await exportLogs(filter: event.filter);
      emit(LogExported(jsonData));
      final logs = await getAllLogs(filter: event.filter);
      emit(LogLoaded(logs, currentFilter: event.filter));
    } catch (e) {
      emit(LogError(e.toString()));
    }
  }

  Future<void> _onApplyFilter(
      ApplyFilterEvent event,
      Emitter<LogState> emit,
      ) async {
    emit(LogLoading());
    try {
      final logs = await getAllLogs(filter: event.filter);
      emit(LogLoaded(logs, currentFilter: event.filter));
    } catch (e) {
      emit(LogError(e.toString()));
    }
  }

  @override
  Future<void> close() {
    _logStreamSubscription?.cancel();
    return super.close();
  }
}