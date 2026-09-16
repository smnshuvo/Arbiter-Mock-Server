import 'dart:math';

import 'package:arbiter_mock_server/data/datasources/share/nearby_share_protocol.dart';
import 'package:arbiter_mock_server/data/datasources/share/nearby_share_service.dart';
import 'package:arbiter_mock_server/data/datasources/share/share_code.dart';
import 'package:arbiter_mock_server/domain/entities/endpoint.dart';
import 'package:arbiter_mock_server/domain/entities/nearby_share.dart';
import 'package:arbiter_mock_server/domain/entities/network_condition.dart';
import 'package:flutter_test/flutter_test.dart';

Endpoint _endpoint(String id, String pattern) => Endpoint(
      id: id,
      profileId: 'p1',
      pattern: pattern,
      method: 'GET',
      matchType: MatchType.exact,
      mode: EndpointMode.mock,
      mockResponse: '{"id":"$id"}',
      statusCode: 201,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      networkCondition: NetworkCondition.edge,
      useConditionalMock: true,
      conditionalMocks: const [
        ConditionalMock(
          type: ConditionalMatchType.queryParam,
          fieldName: 'user',
          fieldValue: '1',
          mockResponse: '{}',
          statusCode: 200,
        ),
      ],
    );

void main() {
  group('NearbyShareProtocol', () {
    test('collection round-trips with order and conditional mocks intact', () {
      final endpoints = [_endpoint('b', 'second'), _endpoint('a', 'first')];
      final decoded = NearbyShareProtocol.decodeCollection(NearbyShareProtocol.encodeCollection(
        deviceName: 'Mac',
        collectionName: 'Payments',
        endpoints: endpoints,
      ));
      expect(decoded.collectionName, 'Payments');
      expect(decoded.deviceName, 'Mac');
      expect(decoded.endpoints.map((e) => e.pattern), ['second', 'first']);
      expect(decoded.endpoints.first, endpoints.first);
    });

    test('offer parses and junk is ignored', () {
      final peer = NearbyShareProtocol.parseOffer(
        NearbyShareProtocol.offer(
            sessionId: 's', deviceName: 'd', collectionName: 'c', endpointCount: 3, port: 9),
        '10.0.0.2',
      );
      expect(peer?.host, '10.0.0.2');
      expect(peer?.endpointCount, 3);
      expect(NearbyShareProtocol.parseOffer('nope'.codeUnits, 'x'), isNull);
      expect(NearbyShareProtocol.parseOffer(NearbyShareProtocol.discoveryRequest(), 'x'), isNull);
    });

    test('broadcast candidates include the real /23 broadcast a /24 guess misses', () {
      final candidates = NearbyShareProtocol.broadcastCandidates('10.21.178.27');
      expect(candidates, contains('10.21.179.255')); // /23
      expect(candidates, contains('10.21.178.255')); // /24
      expect(candidates, contains('10.21.255.255')); // /16
      expect(NearbyShareProtocol.broadcastCandidates('not-an-ip'), isEmpty);
    });

    test('typed addresses parse leniently', () {
      expect(NearbyShareProtocol.parseAddress(' 192.168.1.20:52814 '),
          (host: '192.168.1.20', port: 52814));
      expect(NearbyShareProtocol.parseAddress('http://10.0.0.5:8000/'),
          (host: '10.0.0.5', port: 8000));
      expect(NearbyShareProtocol.parseAddress('192.168.1.20'), isNull);
      expect(NearbyShareProtocol.parseAddress('host:99999'), isNull);
    });

    test('pin is 4 digits and compares exactly', () {
      final pin = NearbyShareProtocol.generatePin(Random(1));
      expect(pin, matches(RegExp(r'^\d{4}$')));
      expect(NearbyShareProtocol.pinMatches(pin, pin), isTrue);
      expect(NearbyShareProtocol.pinMatches('1234', '1235'), isFalse);
      expect(NearbyShareProtocol.pinMatches('1234', null), isFalse);
      expect(NearbyShareProtocol.pinMatches('1234', '12345'), isFalse);
    });
  });

  group('NearbyShareService over loopback', () {
    late NearbyShareService sender;
    late NearbyShareService receiver;

    setUp(() {
      final port = 40000 + Random().nextInt(5000);
      // Port 0 for the share server so tests never fight a running app over
      // the fixed code ports.
      sender = NearbyShareService(discoveryPort: port, sharePorts: const []);
      receiver = NearbyShareService(
          discoveryPort: port,
          probeInterval: const Duration(milliseconds: 200),
          sharePorts: const []);
    });

    tearDown(() => sender.stopSharing());

    test('receiver discovers the sender and downloads with the right PIN', () async {
      final session = await sender.startSharing(
          collectionName: 'Orders', endpoints: [_endpoint('1', 'orders')]);
      final pin = session.pin;
      final delivered = sender.shareEvents.firstWhere((e) => e is ShareDelivered);

      final peers = await receiver
          .discoverPeers()
          .firstWhere((list) => list.isNotEmpty)
          .timeout(const Duration(seconds: 5));
      expect(peers.single.collectionName, 'Orders');
      expect(peers.single.endpointCount, 1);

      final collection = await receiver.fetchCollection(peers.single, pin);
      expect(collection.endpoints.single.pattern, 'orders');
      await delivered.timeout(const Duration(seconds: 2));
    });

    test('connect by address finds the sharer without discovery', () async {
      final session = await sender.startSharing(
          collectionName: 'Manual', endpoints: [_endpoint('1', 'a'), _endpoint('2', 'b')]);
      final peer = await receiver.connectTo('127.0.0.1', session.port);
      expect(peer.collectionName, 'Manual');
      expect(peer.endpointCount, 2);
      final collection = await receiver.fetchCollection(peer, session.pin);
      expect(collection.endpoints.map((e) => e.pattern), ['a', 'b']);
      await expectLater(receiver.connectTo('127.0.0.1', 1), throwsA(isA<NearbyShareException>()));
    });

    test('a share on a fixed port issues a code that decodes to that port and PIN', () async {
      final codeSender = NearbyShareService(discoveryPort: sender.discoveryPort);
      addTearDown(codeSender.stopSharing);
      final session = await codeSender.startSharing(
          collectionName: 'Coded', endpoints: [_endpoint('1', 'coded')]);
      expect(ShareCode.ports, contains(session.port));
      if (session.code == null) {
        markTestSkipped('No private IPv4 address on this machine to encode');
        return;
      }
      final decoded = ShareCode.decode(session.code!)!;
      expect(decoded.port, session.port);
      expect(decoded.pin, session.pin);
      expect(session.addresses, contains(decoded.host));
      // Fetch over loopback with the decoded port + PIN (the LAN IP may be
      // unreachable from a CI sandbox).
      final peer = await receiver.connectTo('127.0.0.1', decoded.port);
      final collection = await receiver.fetchCollection(peer, decoded.pin);
      expect(collection.endpoints.single.pattern, 'coded');
    });

        test('wrong PIN is rejected and rotates after too many attempts', () async {
      final pin = (await sender.startSharing(collectionName: 'X', endpoints: const [])).pin;
      final peer = NearbyPeer(
        sessionId: 's',
        deviceName: 'd',
        collectionName: 'X',
        endpointCount: 0,
        host: '127.0.0.1',
        port: sender.sharePort!,
      );
      final wrong = pin == '0000' ? '1111' : '0000';
      final rotated = sender.shareEvents.firstWhere((e) => e is SharePinRotated);

      await expectLater(
        receiver.fetchCollection(peer, wrong),
        throwsA(isA<NearbyShareException>().having((e) => e.wrongPin, 'wrongPin', isTrue)),
      );
      for (var i = 1; i < NearbyShareProtocol.maxPinAttempts; i++) {
        await receiver.fetchCollection(peer, wrong).catchError((_) => const SharedCollection(
            deviceName: '', collectionName: '', endpoints: []));
      }
      final event = await rotated.timeout(const Duration(seconds: 2)) as SharePinRotated;
      expect(event.session.pin, matches(RegExp(r'^\d{4}$')));
    });
  });
}
