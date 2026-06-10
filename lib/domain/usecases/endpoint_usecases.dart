import '../entities/endpoint.dart';
import '../entities/request_log.dart';
import '../repositories/endpoint_repository.dart';

class GetAllEndpoints {
  final EndpointRepository repository;
  GetAllEndpoints(this.repository);

  Future<List<Endpoint>> call({String? profileId}) async {
    return await repository.getAllEndpoints(profileId: profileId);
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

  Future<void> call(List<Endpoint> endpoints, {required String profileId}) async {
    await repository.importEndpoints(endpoints, profileId: profileId);
  }
}

class ExportEndpoints {
  final EndpointRepository repository;
  ExportEndpoints(this.repository);

  Future<String> call({required String profileId}) async {
    return await repository.exportEndpoints(profileId: profileId);
  }
}

class ToggleAllEndpoints {
  final EndpointRepository repository;
  ToggleAllEndpoints(this.repository);

  Future<void> call({required String profileId, required bool enabled}) async {
    await repository.toggleAllEndpoints(profileId: profileId, enabled: enabled);
  }
}

class BatchCreateEndpointsFromLogs {
  final EndpointRepository repository;
  BatchCreateEndpointsFromLogs(this.repository);

  /// Returns the number of endpoints actually created (duplicates are skipped).
  Future<int> call({
    required List<RequestLog> logs,
    required String profileId,
    required int delayMs,
  }) async {
    int created = 0;
    final now = DateTime.now();
    for (final log in logs) {
      String pattern = log.url;
      if (pattern.contains('?')) pattern = pattern.split('?').first;
      if (pattern.startsWith('/')) pattern = pattern.substring(1);

      final endpoint = Endpoint(
        id: '${now.millisecondsSinceEpoch}_${log.id}',
        profileId: profileId,
        pattern: pattern,
        matchType: MatchType.exact,
        mode: EndpointMode.mock,
        mockResponse: log.responseBody ?? '{}',
        statusCode: log.statusCode,
        delayMs: delayMs,
        targetUrl: null,
        createdAt: now,
        updatedAt: now,
        isEnabled: true,
        conditionalMocks: const [],
        useConditionalMock: false,
      );

      try {
        await repository.createEndpoint(endpoint);
        created++;
      } catch (_) {
        // Skip duplicates silently
      }
    }
    return created;
  }
}
