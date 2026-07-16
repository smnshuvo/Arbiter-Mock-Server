import 'package:flutter_test/flutter_test.dart';
import 'package:arbiter_mock_server/domain/entities/endpoint.dart';
import 'package:arbiter_mock_server/data/models/endpoint_model.dart';

void main() {
  Endpoint sample({String? method}) => Endpoint(
        id: 'e1',
        pattern: '/v1/users',
        method: method,
        matchType: MatchType.wildcard,
        mode: EndpointMode.mock,
        mockResponse: '{"ok":true}',
        statusCode: 201,
        delayMs: 150,
        createdAt: DateTime.parse('2026-07-16T10:00:00.000'),
        updatedAt: DateTime.parse('2026-07-16T10:30:00.000'),
      );

  group('Endpoint.method field', () {
    test('kEndpointMethods lists ANY + the common verbs', () {
      expect(kEndpointMethods.first, 'ANY');
      expect(kEndpointMethods, containsAll(['GET', 'POST', 'PUT', 'PATCH', 'DELETE']));
    });

    test('defaults to null (ANY) when unset', () {
      expect(sample().method, isNull);
    });

    test('copyWith preserves method and can set it', () {
      expect(sample(method: 'GET').copyWith().method, 'GET');
      expect(sample().copyWith(method: 'POST').method, 'POST');
    });

    test('method is part of equality', () {
      expect(sample(method: 'GET'), isNot(equals(sample(method: 'POST'))));
      expect(sample(method: 'GET'), equals(sample(method: 'GET')));
    });
  });

  group('EndpointModel round-trips method', () {
    test('entity -> model -> entity (verb set)', () {
      final back = EndpointModel.fromEntity(sample(method: 'PATCH')).toEntity();
      expect(back.method, 'PATCH');
      expect(back.pattern, '/v1/users');
      expect(back.matchType, MatchType.wildcard);
      expect(back.statusCode, 201);
    });

    test('entity -> model -> entity (ANY/null preserved)', () {
      final back = EndpointModel.fromEntity(sample()).toEntity();
      expect(back.method, isNull);
    });

    test('toMap/fromMap preserves method column', () {
      final map = EndpointModel.fromEntity(sample(method: 'DELETE')).toMap();
      expect(map['method'], 'DELETE');
      expect(EndpointModel.fromMap(map).toEntity().method, 'DELETE');
    });

    test('toJson/fromJson preserves method', () {
      final json = EndpointModel.fromEntity(sample(method: 'PUT')).toJson();
      expect(json['method'], 'PUT');
      expect(EndpointModel.fromJson(json).toEntity().method, 'PUT');
    });

    test('legacy map without method decodes as null', () {
      final map = EndpointModel.fromEntity(sample(method: 'GET')).toMap()
        ..remove('method');
      expect(EndpointModel.fromMap(map).toEntity().method, isNull);
    });
  });
}
