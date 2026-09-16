import 'dart:convert';
import 'dart:math';

import '../../../domain/entities/endpoint.dart';
import '../../../domain/entities/nearby_share.dart';
import '../../models/endpoint_model.dart';

/// Wire format for nearby sharing. Pure functions only, so it's unit-testable
/// without sockets.
///
/// Discovery: the receiver sends [discoveryRequest] to UDP [discoveryPort] via
/// broadcast and via [multicastGroup]; every sharing instance answers the
/// sender address with an offer. Manual fallback: `GET` [infoPath] on a typed
/// `host:port` returns the same offer. Transfer: plain HTTP on the offer's
/// port, `GET` [collectionPath] with the PIN in [pinHeader].
class NearbyShareProtocol {
  NearbyShareProtocol._();

  static const int version = 1;
  static const int discoveryPort = 47777;
  static const String collectionPath = '/arbiter-share/collection';
  static const String infoPath = '/arbiter-share/info';

  /// Organization-local scope, so it never leaves the site. Networks that drop
  /// broadcasts often still pass multicast (and vice versa).
  static const String multicastGroup = '239.255.42.99';
  static const String pinHeader = 'x-arbiter-pin';
  static const int maxPinAttempts = 5;

  static List<int> discoveryRequest() =>
      utf8.encode(jsonEncode({'arbiter': 'discover', 'v': version}));

  static bool isDiscoveryRequest(List<int> bytes) {
    final json = _decodeObject(bytes);
    return json != null && json['arbiter'] == 'discover';
  }

  static List<int> offer({
    required String sessionId,
    required String deviceName,
    required String collectionName,
    required int endpointCount,
    required int port,
  }) =>
      utf8.encode(jsonEncode({
        'arbiter': 'offer',
        'v': version,
        'sid': sessionId,
        'device': deviceName,
        'name': collectionName,
        'count': endpointCount,
        'port': port,
      }));

  /// Directed-broadcast candidates for an interface address. Dart doesn't
  /// expose netmasks, so this covers every prefix from /24 down to /16 — one
  /// of them is the real subnet broadcast (a /23 office network's is x.y.179.255
  /// for 10.21.178.27, which a /24 guess misses). The others are either
  /// dropped by the router or land as a tiny UDP packet on a closed port.
  static List<String> broadcastCandidates(String ipv4) {
    final parts = ipv4.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) return const [];
    final ip = (parts[0]! << 24) | (parts[1]! << 16) | (parts[2]! << 8) | parts[3]!;
    final result = <String>{};
    for (var prefix = 24; prefix >= 16; prefix--) {
      final hostMask = (1 << (32 - prefix)) - 1;
      final b = ip | hostMask;
      result.add('${(b >> 24) & 255}.${(b >> 16) & 255}.${(b >> 8) & 255}.${b & 255}');
    }
    return result.toList();
  }

  /// Parses a typed `host:port` (whitespace and a leading `http://` tolerated).
  static ({String host, int port})? parseAddress(String input) {
    final cleaned = input.trim().replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/.*$'), '');
    final i = cleaned.lastIndexOf(':');
    if (i <= 0) return null;
    final port = int.tryParse(cleaned.substring(i + 1));
    if (port == null || port <= 0 || port > 65535) return null;
    return (host: cleaned.substring(0, i), port: port);
  }

  /// Parses an offer datagram received from [host]; null for anything else.
  static NearbyPeer? parseOffer(List<int> bytes, String host) {
    final json = _decodeObject(bytes);
    if (json == null || json['arbiter'] != 'offer') return null;
    final sid = json['sid'], port = json['port'];
    if (sid is! String || port is! int) return null;
    return NearbyPeer(
      sessionId: sid,
      deviceName: json['device'] as String? ?? 'Unknown device',
      collectionName: json['name'] as String? ?? 'Shared collection',
      endpointCount: json['count'] as int? ?? 0,
      host: host,
      port: port,
    );
  }

  /// Full-fidelity endpoint payload (DB model JSON — includes conditional
  /// mocks, prompt candidates and network condition), order preserved.
  static String encodeCollection({
    required String deviceName,
    required String collectionName,
    required List<Endpoint> endpoints,
  }) =>
      jsonEncode({
        'schema': version,
        'device': deviceName,
        'name': collectionName,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'endpoints': [for (final e in endpoints) EndpointModel.fromEntity(e).toJson()],
      });

  static SharedCollection decodeCollection(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final list = json['endpoints'] as List;
      return SharedCollection(
        deviceName: json['device'] as String? ?? 'Unknown device',
        collectionName: json['name'] as String? ?? 'Shared collection',
        endpoints: [
          for (final e in list) EndpointModel.fromJson(e as Map<String, dynamic>).toEntity(),
        ],
      );
    } catch (_) {
      throw const NearbyShareException('The shared data was not a valid collection.');
    }
  }

  static String generatePin([Random? random]) {
    final r = random ?? Random.secure();
    return r.nextInt(10000).toString().padLeft(4, '0');
  }

  /// Constant-time comparison so response timing doesn't leak digits.
  static bool pinMatches(String expected, String? given) {
    if (given == null || given.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected.codeUnitAt(i) ^ given.codeUnitAt(i);
    }
    return diff == 0;
  }

  static Map<String, dynamic>? _decodeObject(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
