import '../entities/endpoint.dart';

abstract class EndpointRepository {
  Future<List<Endpoint>> getAllEndpoints();
  Future<Endpoint?> getEndpointById(String id);
  Future<void> createEndpoint(Endpoint endpoint);
  Future<void> updateEndpoint(Endpoint endpoint);
  Future<void> deleteEndpoint(String id);
  Future<void> importEndpoints(List<Endpoint> endpoints);
  Future<String> exportEndpoints();
}