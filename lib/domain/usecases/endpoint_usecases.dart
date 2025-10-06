import '../entities/endpoint.dart';
import '../repositories/endpoint_repository.dart';

class GetAllEndpoints {
  final EndpointRepository repository;

  GetAllEndpoints(this.repository);

  Future<List<Endpoint>> call() async {
    return await repository.getAllEndpoints();
  }
}

class CreateEndpoint {
  final EndpointRepository repository;

  CreateEndpoint(this.repository);

  Future<void> call(Endpoint endpoint) async {
    await repository.createEndpoint(endpoint);
  }
}

class UpdateEndpoint {
  final EndpointRepository repository;

  UpdateEndpoint(this.repository);

  Future<void> call(Endpoint endpoint) async {
    await repository.updateEndpoint(endpoint);
  }
}

class DeleteEndpoint {
  final EndpointRepository repository;

  DeleteEndpoint(this.repository);

  Future<void> call(String id) async {
    await repository.deleteEndpoint(id);
  }
}

class ImportEndpoints {
  final EndpointRepository repository;

  ImportEndpoints(this.repository);

  Future<void> call(List<Endpoint> endpoints) async {
    await repository.importEndpoints(endpoints);
  }
}

class ExportEndpoints {
  final EndpointRepository repository;

  ExportEndpoints(this.repository);

  Future<String> call() async {
    return await repository.exportEndpoints();
  }
}