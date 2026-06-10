import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../domain/entities/endpoint.dart';
import '../../../domain/entities/request_log.dart';
import '../../../domain/exceptions/endpoint_exceptions.dart';
import '../../../domain/usecases/endpoint_usecases.dart';

// Events
abstract class EndpointEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadEndpointsEvent extends EndpointEvent {
  final String profileId;
  LoadEndpointsEvent(this.profileId);

  @override
  List<Object?> get props => [profileId];
}

class CreateEndpointEvent extends EndpointEvent {
  final Endpoint endpoint;
  CreateEndpointEvent(this.endpoint);

  @override
  List<Object?> get props => [endpoint];
}

class UpdateEndpointEvent extends EndpointEvent {
  final Endpoint endpoint;
  UpdateEndpointEvent(this.endpoint);

  @override
  List<Object?> get props => [endpoint];
}

class DeleteEndpointEvent extends EndpointEvent {
  final String id;
  final String profileId;
  DeleteEndpointEvent(this.id, this.profileId);

  @override
  List<Object?> get props => [id, profileId];
}

class ImportEndpointsEvent extends EndpointEvent {
  final List<Endpoint> endpoints;
  final String profileId;
  ImportEndpointsEvent(this.endpoints, this.profileId);

  @override
  List<Object?> get props => [endpoints, profileId];
}

class ExportEndpointsEvent extends EndpointEvent {
  final String profileId;
  ExportEndpointsEvent(this.profileId);

  @override
  List<Object?> get props => [profileId];
}

class ToggleAllEndpointsEvent extends EndpointEvent {
  final String profileId;
  final bool enabled;
  ToggleAllEndpointsEvent({required this.profileId, required this.enabled});

  @override
  List<Object?> get props => [profileId, enabled];
}

class BatchCreateEndpointsFromLogsEvent extends EndpointEvent {
  final List<RequestLog> logs;
  final String profileId;
  final int delayMs;
  BatchCreateEndpointsFromLogsEvent({
    required this.logs,
    required this.profileId,
    required this.delayMs,
  });

  @override
  List<Object?> get props => [logs, profileId, delayMs];
}

class BatchCreateSuccessState extends EndpointState {
  final int count;
  final String profileId;
  BatchCreateSuccessState(this.count, this.profileId);

  @override
  List<Object?> get props => [count, profileId];
}

// States
abstract class EndpointState extends Equatable {
  @override
  List<Object?> get props => [];
}

class EndpointInitial extends EndpointState {}

class EndpointLoading extends EndpointState {}

class EndpointDuplicateFound extends EndpointState {
  final Endpoint existing;
  final Endpoint incoming;
  EndpointDuplicateFound({required this.existing, required this.incoming});

  @override
  List<Object?> get props => [existing, incoming];
}

class EndpointLoaded extends EndpointState {
  final List<Endpoint> endpoints;
  final String profileId;

  EndpointLoaded(this.endpoints, this.profileId);

  @override
  List<Object?> get props => [endpoints, profileId];
}

class EndpointExported extends EndpointState {
  final String jsonData;

  EndpointExported(this.jsonData);

  @override
  List<Object?> get props => [jsonData];
}

class EndpointError extends EndpointState {
  final String message;

  EndpointError(this.message);

  @override
  List<Object?> get props => [message];
}

// BLoC
class EndpointBloc extends Bloc<EndpointEvent, EndpointState> {
  final GetAllEndpoints getAllEndpoints;
  final CreateEndpoint createEndpoint;
  final UpdateEndpoint updateEndpoint;
  final DeleteEndpoint deleteEndpoint;
  final ImportEndpoints importEndpoints;
  final ExportEndpoints exportEndpoints;
  final ToggleAllEndpoints toggleAllEndpoints;
  final BatchCreateEndpointsFromLogs batchCreateEndpointsFromLogs;

  EndpointBloc({
    required this.getAllEndpoints,
    required this.createEndpoint,
    required this.updateEndpoint,
    required this.deleteEndpoint,
    required this.importEndpoints,
    required this.exportEndpoints,
    required this.toggleAllEndpoints,
    required this.batchCreateEndpointsFromLogs,
  }) : super(EndpointInitial()) {
    on<LoadEndpointsEvent>(_onLoadEndpoints);
    on<CreateEndpointEvent>(_onCreateEndpoint);
    on<UpdateEndpointEvent>(_onUpdateEndpoint);
    on<DeleteEndpointEvent>(_onDeleteEndpoint);
    on<ImportEndpointsEvent>(_onImportEndpoints);
    on<ExportEndpointsEvent>(_onExportEndpoints);
    on<ToggleAllEndpointsEvent>(_onToggleAllEndpoints);
    on<BatchCreateEndpointsFromLogsEvent>(_onBatchCreateFromLogs);
  }

  Future<void> _onLoadEndpoints(LoadEndpointsEvent event, Emitter<EndpointState> emit) async {
    emit(EndpointLoading());
    try {
      final endpoints = await getAllEndpoints(profileId: event.profileId);
      emit(EndpointLoaded(endpoints, event.profileId));
    } catch (e) {
      emit(EndpointError(e.toString()));
    }
  }

  Future<void> _onCreateEndpoint(CreateEndpointEvent event, Emitter<EndpointState> emit) async {
    try {
      await createEndpoint(event.endpoint);
      final endpoints = await getAllEndpoints(profileId: event.endpoint.profileId);
      emit(EndpointLoaded(endpoints, event.endpoint.profileId));
    } on DuplicateEndpointException catch (e) {
      emit(EndpointDuplicateFound(existing: e.existing, incoming: event.endpoint));
    } catch (e) {
      emit(EndpointError(e.toString()));
    }
  }

  Future<void> _onUpdateEndpoint(UpdateEndpointEvent event, Emitter<EndpointState> emit) async {
    try {
      await updateEndpoint(event.endpoint);
      final endpoints = await getAllEndpoints(profileId: event.endpoint.profileId);
      emit(EndpointLoaded(endpoints, event.endpoint.profileId));
    } catch (e) {
      emit(EndpointError(e.toString()));
    }
  }

  Future<void> _onDeleteEndpoint(DeleteEndpointEvent event, Emitter<EndpointState> emit) async {
    try {
      await deleteEndpoint(event.id);
      final endpoints = await getAllEndpoints(profileId: event.profileId);
      emit(EndpointLoaded(endpoints, event.profileId));
    } catch (e) {
      emit(EndpointError(e.toString()));
    }
  }

  Future<void> _onImportEndpoints(ImportEndpointsEvent event, Emitter<EndpointState> emit) async {
    emit(EndpointLoading());
    try {
      await importEndpoints(event.endpoints, profileId: event.profileId);
      final endpoints = await getAllEndpoints(profileId: event.profileId);
      emit(EndpointLoaded(endpoints, event.profileId));
    } catch (e) {
      emit(EndpointError(e.toString()));
    }
  }

  Future<void> _onExportEndpoints(ExportEndpointsEvent event, Emitter<EndpointState> emit) async {
    try {
      final jsonData = await exportEndpoints(profileId: event.profileId);
      emit(EndpointExported(jsonData));
      final endpoints = await getAllEndpoints(profileId: event.profileId);
      emit(EndpointLoaded(endpoints, event.profileId));
    } catch (e) {
      emit(EndpointError(e.toString()));
    }
  }

  Future<void> _onToggleAllEndpoints(ToggleAllEndpointsEvent event, Emitter<EndpointState> emit) async {
    try {
      await toggleAllEndpoints(profileId: event.profileId, enabled: event.enabled);
      final endpoints = await getAllEndpoints(profileId: event.profileId);
      emit(EndpointLoaded(endpoints, event.profileId));
    } catch (e) {
      emit(EndpointError(e.toString()));
    }
  }

  Future<void> _onBatchCreateFromLogs(BatchCreateEndpointsFromLogsEvent event, Emitter<EndpointState> emit) async {
    emit(EndpointLoading());
    try {
      final created = await batchCreateEndpointsFromLogs(
        logs: event.logs,
        profileId: event.profileId,
        delayMs: event.delayMs,
      );
      emit(BatchCreateSuccessState(created, event.profileId));
    } catch (e) {
      emit(EndpointError(e.toString()));
    }
  }
}
