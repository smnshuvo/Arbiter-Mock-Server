import 'dart:async';

import 'package:arbiter_mock_server/core/services/server_manager.dart';
import 'package:arbiter_mock_server/data/datasources/local/log_local_datasource.dart';
import 'package:arbiter_mock_server/data/datasources/server/interception_manager.dart';
import 'package:arbiter_mock_server/data/datasources/server/prompt_interception_manager.dart';
import 'package:arbiter_mock_server/data/models/request_log_model.dart';
import 'package:arbiter_mock_server/domain/entities/endpoint.dart';
import 'package:arbiter_mock_server/domain/entities/request_log.dart';
import 'package:arbiter_mock_server/domain/repositories/log_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _FakeLogDataSource implements LogLocalDataSource {
  final List<RequestLogModel> logs = [];
  final _controller = StreamController<RequestLog>.broadcast();
  @override
  Future<void> insertLog(RequestLogModel log) async => logs.add(log);
  @override
  Stream<RequestLog> get newLogStream => _controller.stream;
  @override
  Future<void> clearLogs() async => logs.clear();
  @override
  Future<void> clearFilteredLogs(LogFilter filter) async {}
  @override
  Future<void> deleteLogsByIds(List<String> ids) async {}
  @override
  Future<List<RequestLogModel>> getAllLogs({LogFilter? filter}) async => logs;
  @override
  Future<RequestLogModel?> getLogById(String id) async => null;
}

void main() {
  test(
      'a newly-created endpoint is reachable on the very first request, '
      'without waiting for the next request to trigger a lazy refresh', () async {
    // onEndpointsNeeded intentionally returns an empty list forever here —
    // this reproduces the bug: the only way the endpoint becomes reachable is
    // via the eager ServerManager.updateEndpoints push, not the per-request
    // fire-and-forget refresh.
    final manager = ServerManager(
      logDataSource: _FakeLogDataSource(),
      interceptionManager: InterceptionManager(),
      promptInterceptionManager: PromptInterceptionManager(),
      onEndpointsNeeded: (profileId) async => const [],
    );

    const profileId = 'p1';
    await manager.startProfile(
      profileId: profileId,
      profileName: 'Test',
      port: 8940,
    );

    final endpoint = Endpoint(
      id: 'e1',
      profileId: profileId,
      pattern: '/fresh',
      matchType: MatchType.exact,
      mode: EndpointMode.mock,
      mockResponse: '{"ok":true}',
      statusCode: 200,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Mirrors what EndpointBloc now does right after CreateEndpointEvent.
    manager.updateEndpoints(profileId, [endpoint]);

    final res = await http.get(Uri.parse('http://localhost:8940/fresh'));
    expect(res.statusCode, 200);

    await manager.stopProfile(profileId);
  });

  test(
      'an endpoint that already existed before the server started is '
      'reachable on the very first request after startProfile', () async {
    final endpoint = Endpoint(
      id: 'e2',
      profileId: 'p2',
      pattern: '/already-there',
      matchType: MatchType.exact,
      mode: EndpointMode.mock,
      mockResponse: '{"ok":true}',
      statusCode: 200,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Simulates real startup: the endpoint was loaded from the DB well before
    // the server ever starts, so nothing calls ServerManager.updateEndpoints
    // for it — startProfile itself must warm the cache.
    final manager = ServerManager(
      logDataSource: _FakeLogDataSource(),
      interceptionManager: InterceptionManager(),
      promptInterceptionManager: PromptInterceptionManager(),
      onEndpointsNeeded: (profileId) async => [endpoint],
    );

    await manager.startProfile(
      profileId: 'p2',
      profileName: 'Test',
      port: 8941,
    );

    final res = await http.get(Uri.parse('http://localhost:8941/already-there'));
    expect(res.statusCode, 200);

    await manager.stopProfile('p2');
  });
}
