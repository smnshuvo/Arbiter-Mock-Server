import '../entities/endpoint.dart';

class DuplicateEndpointException implements Exception {
  final Endpoint existing;
  DuplicateEndpointException(this.existing);

  @override
  String toString() =>
      'An endpoint with pattern "${existing.pattern}" already exists in this profile';
}
