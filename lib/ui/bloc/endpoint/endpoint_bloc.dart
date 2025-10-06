import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../domain/entities/endpoint.dart';
import '../../../domain/usecases/endpoint_usecases.dart';

// Events
abstract class EndpointEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadEndpointsEvent extends EndpointEvent {}

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
  DeleteEndpointEvent(this.id);

  @override
  List<Object?> get props => [id];
}

class ImportEndpointsEvent extends EndpointEvent {
  final List<Endpoint> endpoints;
  ImportEndpointsEvent(this.endpoints);

  @override
  List<Object?> get props => [endpoints];
}

class ExportEndpointsEvent extends EndpointEvent {}

// States
abstract class EndpointState extends Equatable {
  @override
  List<Object?> get props => [];
}

class EndpointInitial extends EndpointState {}

class EndpointLoading extends EndpointState {}

class EndpointLoaded extends EndpointState {
  final List<Endpoint> endpoints;

  EndpointLoaded(this.endpoints);

  @override
  List<Object?> get props => [endpoints];
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

  EndpointBloc({
    required this.getAllEndpoints,
    required this.createEndpoint,
    required this.updateEndpoint,
    required this.deleteEndpoint,
    required this.importEndpoints,
    required this.exportEndpoints,
  }) : super(EndpointInitial()) {
    on<LoadEndpointsEvent>(_onLoadEndpoints);
    on<CreateEndpointEvent>(_onCreateEndpoint);
    on<UpdateEndpointEvent>(_onUpdateEndpoint);
    on<DeleteEndpointEvent>(_onDeleteEndpoint);
    on<ImportEndpointsEvent>(_onImportEndpoints);
    on<ExportEndpointsEvent>(_onExportEndpoints);
  }

  Future<void> _onLoadEndpoints(
      LoadEndpointsEvent event,
      Emitter<EndpointState> emit,
      ) async {
    emit(EndpointLoading());
    try {
      final endpoints = await getAllEndpoints();
      emit(EndpointLoaded(endpoints));
    } catch (e) {
      emit(EndpointError(e.toString()));
    }
  }

  Future<void> _onCreateEndpoint(
      CreateEndpointEvent event,
      Emitter<EndpointState> emit,
      ) async {
    try {
      await createEndpoint(event.endpoint);
      final endpoints = await getAllEndpoints();
      emit(EndpointLoaded(endpoints));
    } catch (e) {
      emit(EndpointError(e.toString()));
    }
  }

  Future<void> _onUpdateEndpoint(
      UpdateEndpointEvent event,
      Emitter<EndpointState> emit,
      ) async {
    try {
      await updateEndpoint(event.endpoint);
      final endpoints = await getAllEndpoints();
      emit(EndpointLoaded(endpoints));
    } catch (e) {
      emit(EndpointError(e.toString()));
    }
  }

  Future<void> _onDeleteEndpoint(
      DeleteEndpointEvent event,
      Emitter<EndpointState> emit,
      ) async {
    try {
      await deleteEndpoint(event.id);
      final endpoints = await getAllEndpoints();
      emit(EndpointLoaded(endpoints));
    } catch (e) {
      emit(EndpointError(e.toString()));
    }
  }

  Future<void> _onImportEndpoints(
      ImportEndpointsEvent event,
      Emitter<EndpointState> emit,
      ) async {
    emit(EndpointLoading());
    try {
      await importEndpoints(event.endpoints);
      final endpoints = await getAllEndpoints();
      emit(EndpointLoaded(endpoints));
    } catch (e) {
      emit(EndpointError(e.toString()));
    }
  }

  Future<void> _onExportEndpoints(
      ExportEndpointsEvent event,
      Emitter<EndpointState> emit,
      ) async {
    try {
      final jsonData = await exportEndpoints();
      emit(EndpointExported(jsonData));
      final endpoints = await getAllEndpoints();
      emit(EndpointLoaded(endpoints));
    } catch (e) {
      emit(EndpointError(e.toString()));
    }
  }
}