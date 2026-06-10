import '../entities/endpoint.dart';

abstract class EndpointRepository {
  Future<List<Endpoint>> getAllEndpoints({String? profileId});
  Future<Endpoint?> getEndpointById(String id);
  Future<void> createEndpoint(Endpoint endpoint);
  Future<void> updateEndpoint(Endpoint endpoint);
  Future<void> deleteEndpoint(String id);
  Future<void> importEndpoints(List<Endpoint> endpoints, {required String profileId});
  Future<String> exportEndpoints({required String profileId});
  Future<void> toggleAllEndpoints({required String profileId, required bool enabled});
}