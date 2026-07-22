import 'dart:async';
import 'dart:convert';

import 'package:arbiter_mock_server/data/datasources/local/log_local_datasource.dart';
import 'package:arbiter_mock_server/data/datasources/server/http_server_service.dart';
import 'package:arbiter_mock_server/data/datasources/server/interception_manager.dart';
import 'package:arbiter_mock_server/data/datasources/server/prompt_interception_manager.dart';
import 'package:arbiter_mock_server/data/models/request_log_model.dart';
import 'package:arbiter_mock_server/domain/entities/endpoint.dart';
import 'package:arbiter_mock_server/domain/entities/network_condition.dart';
import 'package:arbiter_mock_server/domain/entities/request_log.dart';
import 'package:arbiter_mock_server/domain/repositories/log_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// In-memory log sink — keeps the server off sqflite.
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
  Future<List<RequestLogModel>> getAllLogs({LogFilter? filter}) async => logs;

  @override
  Future<RequestLogModel?> getLogById(String id) async => null;
}

void main() {
  late HttpServerService service;
  late _FakeLogDataSource logs;

  Endpoint endpoint({
    required NetworkCondition condition,
    required String body,
  }) =>
      Endpoint(
        id: 'e1',
        pattern: '/throttled',
        matchType: MatchType.exact,
        mode: EndpointMode.mock,
        mockResponse: body,
        statusCode: 200,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        networkCondition: condition,
      );

  // A fresh port per bind, so a just-closed socket in TIME_WAIT can't make
  // the next test flake.
  int nextPort = 8931;

  setUp(() {
    logs = _FakeLogDataSource();
    service = HttpServerService(
      logDataSource: logs,
      onEndpointsNeeded: () {},
      interceptionManager: InterceptionManager(),
      promptInterceptionManager: PromptInterceptionManager(),
    );
  });

  tearDown(() async {
    if (service.isRunning) await service.stop();
  });

  Future<Uri> start(Endpoint e) async {
    service.updateEndpoints([e]);
    final port = nextPort++;
    await service.start(port);
    return Uri.parse('http://localhost:$port/throttled');
  }

  test('an unthrottled endpoint responds promptly', () async {
    final uri = await start(
        endpoint(condition: NetworkCondition.none, body: '{"ok":true}'));

    final sw = Stopwatch()..start();
    final res = await http.get(uri);
    sw.stop();

    expect(res.statusCode, 200);
    expect(res.body, '{"ok":true}');
    expect(sw.elapsedMilliseconds, lessThan(300));
  });

  test('GPRS delays the response by at least its latency', () async {
    final uri = await start(
        endpoint(condition: NetworkCondition.gprs, body: '{"ok":true}'));

    final sw = Stopwatch()..start();
    final res = await http.get(uri);
    sw.stop();

    expect(res.statusCode, 200);
    expect(res.body, '{"ok":true}');
    // GPRS latency is 500 ms before jitter/transfer.
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(500));
  });

  test('a bigger body takes longer on the same link', () async {
    final small = await start(
        endpoint(condition: NetworkCondition.gprs, body: '{"ok":true}'));
    final swSmall = Stopwatch()..start();
    await http.get(small);
    swSmall.stop();
    await service.stop();

    // ~20 KB at 50 kbps ≈ 3.2 s of transfer on top of latency.
    final bigBody = jsonEncode({'data': 'x' * 20000});
    final large =
        await start(endpoint(condition: NetworkCondition.gprs, body: bigBody));
    final swLarge = Stopwatch()..start();
    final res = await http.get(large);
    swLarge.stop();

    expect(res.body.length, bigBody.length);
    expect(swLarge.elapsedMilliseconds,
        greaterThan(swSmall.elapsedMilliseconds + 1000),
        reason: 'transfer time should scale with payload size');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('5G is much faster than GPRS for the same payload', () async {
    final body = jsonEncode({'data': 'x' * 20000});

    final gprsUri = await start(endpoint(condition: NetworkCondition.gprs, body: body));
    final swGprs = Stopwatch()..start();
    await http.get(gprsUri);
    swGprs.stop();
    await service.stop();

    final fiveGUri =
        await start(endpoint(condition: NetworkCondition.fiveG, body: body));
    final swFiveG = Stopwatch()..start();
    await http.get(fiveGUri);
    swFiveG.stop();

    expect(swFiveG.elapsedMilliseconds, lessThan(swGprs.elapsedMilliseconds));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('throttling still applies the endpoint status code', () async {
    final e = Endpoint(
      id: 'e1',
      pattern: '/throttled',
      matchType: MatchType.exact,
      mode: EndpointMode.mock,
      mockResponse: '{"err":true}',
      statusCode: 418,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      networkCondition: NetworkCondition.fiveG,
    );
    final uri = await start(e);
    final res = await http.get(uri);
    expect(res.statusCode, 418);
  });

  test('the response is logged with the simulated time', () async {
    final uri = await start(
        endpoint(condition: NetworkCondition.gprs, body: '{"ok":true}'));
    await http.get(uri);

    expect(logs.logs, hasLength(1));
    expect(logs.logs.single.responseTimeMs, greaterThanOrEqualTo(500),
        reason: 'the log should reflect the delay the client actually saw');
  });
}
