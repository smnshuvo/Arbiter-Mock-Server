import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../domain/entities/request_log.dart';
import '../../../domain/repositories/log_repository.dart';
import '../../../domain/usecases/log_usecases.dart';

const int _kMaxLiveLogCount = 200;

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

class StartWatchingLogsEvent extends LogEvent {
  final LogFilter? filter;
  StartWatchingLogsEvent({this.filter});

  @override
  List<Object?> get props => [filter];
}

class StopWatchingLogsEvent extends LogEvent {}

class _NewLogArrivedEvent extends LogEvent {
  final RequestLog log;
  _NewLogArrivedEvent(this.log);

  @override
  List<Object?> get props => [log];
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
  final bool isStreaming;

  LogLoaded(this.logs, {this.currentFilter, this.isStreaming = false});

  LogLoaded copyWith({
    List<RequestLog>? logs,
    LogFilter? currentFilter,
    bool? isStreaming,
  }) {
    return LogLoaded(
      logs ?? this.logs,
      currentFilter: currentFilter ?? this.currentFilter,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  @override
  List<Object?> get props => [logs, currentFilter, isStreaming];
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
  final WatchNewLogs watchNewLogs;

  StreamSubscription<RequestLog>? _logSubscription;

  LogBloc({
    required this.getAllLogs,
    required this.clearLogs,
    required this.clearFilteredLogs,
    required this.exportLogs,
    required this.watchNewLogs,
  }) : super(LogInitial()) {
    on<LoadLogsEvent>(_onLoadLogs);
    on<ClearLogsEvent>(_onClearLogs);
    on<ClearFilteredLogsEvent>(_onClearFilteredLogs);
    on<ExportLogsEvent>(_onExportLogs);
    on<ApplyFilterEvent>(_onApplyFilter);
    on<StartWatchingLogsEvent>(_onStartWatching);
    on<StopWatchingLogsEvent>(_onStopWatching);
    on<_NewLogArrivedEvent>(_onNewLogArrived);
  }

  @override
  Future<void> close() {
    _logSubscription?.cancel();
    return super.close();
  }

  Future<void> _onLoadLogs(LoadLogsEvent event, Emitter<LogState> emit) async {
    emit(LogLoading());
    try {
      final logs = await getAllLogs(filter: event.filter);
      emit(LogLoaded(logs, currentFilter: event.filter));
    } catch (e) {
      emit(LogError(e.toString()));
    }
  }

  Future<void> _onClearLogs(ClearLogsEvent event, Emitter<LogState> emit) async {
    try {
      await clearLogs();
      final wasStreaming = state is LogLoaded && (state as LogLoaded).isStreaming;
      final currentFilter = state is LogLoaded ? (state as LogLoaded).currentFilter : null;
      emit(LogLoaded([], currentFilter: currentFilter, isStreaming: wasStreaming));
    } catch (e) {
      emit(LogError(e.toString()));
    }
  }

  Future<void> _onClearFilteredLogs(ClearFilteredLogsEvent event, Emitter<LogState> emit) async {
    try {
      await clearFilteredLogs(event.filter);
      final wasStreaming = state is LogLoaded && (state as LogLoaded).isStreaming;
      final logs = await getAllLogs(filter: event.filter);
      emit(LogLoaded(logs, currentFilter: event.filter, isStreaming: wasStreaming));
    } catch (e) {
      emit(LogError(e.toString()));
    }
  }

  Future<void> _onExportLogs(ExportLogsEvent event, Emitter<LogState> emit) async {
    try {
      final jsonData = await exportLogs(filter: event.filter);
      emit(LogExported(jsonData));
      final wasStreaming = state is LogLoaded && (state as LogLoaded).isStreaming;
      final logs = await getAllLogs(filter: event.filter);
      emit(LogLoaded(logs, currentFilter: event.filter, isStreaming: wasStreaming));
    } catch (e) {
      emit(LogError(e.toString()));
    }
  }

  Future<void> _onApplyFilter(ApplyFilterEvent event, Emitter<LogState> emit) async {
    emit(LogLoading());
    try {
      final logs = await getAllLogs(filter: event.filter);
      emit(LogLoaded(logs, currentFilter: event.filter));
    } catch (e) {
      emit(LogError(e.toString()));
    }
  }

  Future<void> _onStartWatching(StartWatchingLogsEvent event, Emitter<LogState> emit) async {
    // Cancel any existing subscription first
    await _logSubscription?.cancel();
    _logSubscription = null;

    emit(LogLoading());
    try {
      final logs = await getAllLogs(filter: event.filter);
      emit(LogLoaded(logs, currentFilter: event.filter, isStreaming: true));

      _logSubscription = watchNewLogs().listen((log) {
        add(_NewLogArrivedEvent(log));
      });
    } catch (e) {
      emit(LogError(e.toString()));
    }
  }

  Future<void> _onStopWatching(StopWatchingLogsEvent event, Emitter<LogState> emit) async {
    await _logSubscription?.cancel();
    _logSubscription = null;

    if (state is LogLoaded) {
      emit((state as LogLoaded).copyWith(isStreaming: false));
    }
  }

  void _onNewLogArrived(_NewLogArrivedEvent event, Emitter<LogState> emit) {
    if (state is! LogLoaded) return;
    final current = state as LogLoaded;

    // Apply active profile/filter: only show this log if it matches
    final filter = current.currentFilter;
    if (filter?.profileId != null && event.log.profileId != filter!.profileId) return;

    final updated = [event.log, ...current.logs];
    final capped = updated.length > _kMaxLiveLogCount
        ? updated.sublist(0, _kMaxLiveLogCount)
        : updated;

    emit(current.copyWith(logs: capped));
  }
}
