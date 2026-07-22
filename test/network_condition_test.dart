import 'dart:math';

import 'package:arbiter_mock_server/data/models/endpoint_model.dart';
import 'package:arbiter_mock_server/domain/entities/endpoint.dart';
import 'package:arbiter_mock_server/domain/entities/network_condition.dart';
import 'package:flutter_test/flutter_test.dart';

/// Random stub returning fixed values, so jitter/timeout rolls are pinned.
class _FixedRandom implements Random {
  _FixedRandom({this.intValue = 0, this.doubleValue = 0});

  final int intValue;
  final double doubleValue;

  @override
  int nextInt(int max) => intValue % max;

  @override
  double nextDouble() => doubleValue;

  @override
  bool nextBool() => false;
}

void main() {
  Endpoint sample({NetworkCondition condition = NetworkCondition.none}) =>
      Endpoint(
        id: 'e1',
        pattern: '/v1/users',
        matchType: MatchType.exact,
        mode: EndpointMode.mock,
        mockResponse: '{"ok":true}',
        createdAt: DateTime.parse('2026-07-16T10:00:00.000'),
        updatedAt: DateTime.parse('2026-07-16T10:30:00.000'),
        networkCondition: condition,
      );

  group('NetworkConditionSpec.delayFor', () {
    test('none applies no delay regardless of size', () {
      final spec = NetworkCondition.none.spec;
      expect(spec.delayFor(1000000), Duration.zero);
    });

    test('adds latency plus transfer time at the given bandwidth', () {
      // GPRS: 50 kbps, 500 ms latency. 1000 bytes = 8000 bits = 160 ms.
      final spec = NetworkCondition.gprs.spec;
      final d = spec.delayFor(1000, random: _FixedRandom());
      expect(d, const Duration(milliseconds: 660));
    });

    test('transfer time scales with payload size', () {
      final spec = NetworkCondition.gprs.spec;
      final small = spec.delayFor(1000, random: _FixedRandom());
      final large = spec.delayFor(10000, random: _FixedRandom());
      // 10x the bytes → 10x the transfer term (160 → 1600 ms).
      expect(large - small, const Duration(milliseconds: 1440));
    });

    test('a faster generation is faster for the same payload', () {
      const bytes = 200000; // 200 KB
      final ordered = [
        NetworkCondition.gprs,
        NetworkCondition.edge,
        NetworkCondition.threeG,
        NetworkCondition.fourG,
        NetworkCondition.fiveG,
      ].map((c) => c.spec.delayFor(bytes, random: _FixedRandom())).toList();

      for (var i = 1; i < ordered.length; i++) {
        expect(ordered[i], lessThan(ordered[i - 1]),
            reason: 'each generation should beat the previous one');
      }
    });

    test('jitter is bounded by jitterMs', () {
      final spec = NetworkCondition.edge.spec;
      final low = spec.delayFor(0, random: _FixedRandom(intValue: 0));
      final high =
          spec.delayFor(0, random: _FixedRandom(intValue: spec.jitterMs));
      expect(low, Duration(milliseconds: spec.latencyMs));
      expect(high, Duration(milliseconds: spec.latencyMs + spec.jitterMs));
    });
  });

  group('NetworkConditionSpec.rollTimeout', () {
    test('stable conditions never time out', () {
      for (final c in NetworkCondition.values) {
        if (c == NetworkCondition.unstable2G) continue;
        expect(c.spec.rollTimeout(random: _FixedRandom(doubleValue: 0.0)),
            isFalse,
            reason: '$c should never time out');
      }
    });

    test('unstable 2G times out below its probability and not above', () {
      final spec = NetworkCondition.unstable2G.spec;
      expect(spec.rollTimeout(random: _FixedRandom(doubleValue: 0.0)), isTrue);
      expect(spec.rollTimeout(random: _FixedRandom(doubleValue: 0.99)), isFalse);
    });

    test('only unstable 2G is marked unstable', () {
      final unstable =
          NetworkCondition.values.where((c) => c.spec.isUnstable).toList();
      expect(unstable, [NetworkCondition.unstable2G]);
    });
  });

  group('persistence', () {
    test('round-trips through EndpointModel', () {
      final model =
          EndpointModel.fromEntity(sample(condition: NetworkCondition.threeG));
      expect(model.networkCondition, 'threeG');
      expect(model.toEntity().networkCondition, NetworkCondition.threeG);
    });

    test('a pre-v6 row with no networkCondition column loads as none', () {
      final model = EndpointModel.fromMap({
        'id': 'e1',
        'profileId': 'default',
        'pattern': '/v1/users',
        'method': null,
        'matchType': 'exact',
        'mode': 'mock',
        'mockResponse': '{}',
        'statusCode': 200,
        'delayMs': 0,
        'targetUrl': null,
        'createdAt': '2026-07-16T10:00:00.000',
        'updatedAt': '2026-07-16T10:00:00.000',
        'isEnabled': 1,
        // no 'networkCondition' key at all
      });
      expect(model.toEntity().networkCondition, NetworkCondition.none);
    });

    test('an unknown condition name degrades to none', () {
      expect(NetworkConditionX.fromName('6G'), NetworkCondition.none);
      expect(NetworkConditionX.fromName(null), NetworkCondition.none);
    });

    test('export JSON carries the condition', () {
      final json =
          EndpointModel.fromEntity(sample(condition: NetworkCondition.unstable2G))
              .toJson();
      expect(json['networkCondition'], 'unstable2G');
    });
  });

  group('Endpoint entity', () {
    test('defaults to no throttling', () {
      expect(sample().networkCondition, NetworkCondition.none);
      expect(sample().networkCondition.isThrottled, isFalse);
    });

    test('copyWith preserves and overrides the condition', () {
      final e = sample(condition: NetworkCondition.edge);
      expect(e.copyWith(statusCode: 404).networkCondition, NetworkCondition.edge);
      expect(e.copyWith(networkCondition: NetworkCondition.fiveG).networkCondition,
          NetworkCondition.fiveG);
    });
  });
}
