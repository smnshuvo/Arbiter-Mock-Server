import 'dart:convert';
import '../../domain/entities/endpoint.dart';
import '../../domain/repositories/endpoint_repository.dart';
import '../datasources/local/endpoint_local_datasource.dart';
import '../models/endpoint_model.dart';

class EndpointRepositoryImpl implements EndpointRepository {
  final EndpointLocalDataSource localDataSource;

  EndpointRepositoryImpl(this.localDataSource);

  @override
  Future<List<Endpoint>> getAllEndpoints({String? profileId}) async {
    final models = await localDataSource.getAllEndpoints(profileId: profileId);
    return models.map((model) => model.toEntity()).toList();
  }

  @override
  Future<Endpoint?> getEndpointById(String id) async {
    final model = await localDataSource.getEndpointById(id);
    return model?.toEntity();
  }

  @override
  Future<void> createEndpoint(Endpoint endpoint) async {
    final model = EndpointModel.fromEntity(endpoint);
    await localDataSource.insertEndpoint(model);
  }

  @override
  Future<void> updateEndpoint(Endpoint endpoint) async {
    final model = EndpointModel.fromEntity(endpoint);
    // Patch if doesn't exist, create
    if (await localDataSource.getEndpointById(model.id) == null) {
      await createEndpoint(model.toEntity());
    } else {
      await localDataSource.updateEndpoint(model);
    }
  }

  @override
  Future<void> deleteEndpoint(String id) async {
    await localDataSource.deleteEndpoint(id);
  }

  @override
  Future<void> importEndpoints(List<Endpoint> endpoints, {required String profileId}) async {
    await localDataSource.deleteAllEndpoints(profileId: profileId);
    for (final endpoint in endpoints) {
      final model = EndpointModel.fromEntity(endpoint.copyWith(profileId: profileId));
      await localDataSource.insertEndpoint(model);
    }
  }

  @override
  Future<String> exportEndpoints({required String profileId}) async {
    final models = await localDataSource.getAllEndpoints(profileId: profileId);
    final jsonList = models.map((model) => model.toJson()).toList();
    return jsonEncode({
      'version': '1.0',
      'exportDate': DateTime.now().toIso8601String(),
      'endpoints': jsonList,
    });
  }

  @override
  Future<void> toggleAllEndpoints({required String profileId, required bool enabled}) async {
    await localDataSource.toggleAllEndpoints(profileId: profileId, enabled: enabled);
  }
}