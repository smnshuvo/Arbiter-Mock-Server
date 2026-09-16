import 'package:equatable/equatable.dart';

import 'endpoint.dart';

/// Another Arbiter instance on the LAN that is currently sharing a collection,
/// as found by nearby discovery.
class NearbyPeer extends Equatable {
  /// Random per-share-session id — dedupes the same sender answering on
  /// several interfaces (e.g. loopback + Wi-Fi when both apps share a machine).
  final String sessionId;
  final String deviceName;
  final String collectionName;
  final int endpointCount;
  final String host;
  final int port;

  const NearbyPeer({
    required this.sessionId,
    required this.deviceName,
    required this.collectionName,
    required this.endpointCount,
    required this.host,
    required this.port,
  });

  @override
  List<Object?> get props => [sessionId, deviceName, collectionName, endpointCount, host, port];
}

/// A collection received from a peer, not yet saved. Endpoint order is kept
/// exactly as sent — first match wins, so order is behavior.
class SharedCollection extends Equatable {
  final String deviceName;
  final String collectionName;
  final List<Endpoint> endpoints;

  const SharedCollection({
    required this.deviceName,
    required this.collectionName,
    required this.endpoints,
  });

  @override
  List<Object?> get props => [deviceName, collectionName, endpoints];
}

/// An active share: the PIN receivers must enter, and where to reach it when
/// discovery can't — as a short [code] (address + port + PIN) or, failing
/// that, a typed `address:port`.
class ShareSession {
  final String pin;
  final int port;
  final List<String> addresses;

  /// 9-character pairing code, or null when no private IPv4 address / fixed
  /// share port was available to encode.
  final String? code;

  const ShareSession({
    required this.pin,
    required this.port,
    required this.addresses,
    this.code,
  });
}

/// Sender-side events for the share dialog.
sealed class ShareEvent {
  const ShareEvent();
}

/// Too many wrong PINs — a fresh PIN (and so a fresh code) was generated.
class SharePinRotated extends ShareEvent {
  final ShareSession session;
  const SharePinRotated(this.session);
}

/// A receiver entered the right PIN and downloaded the collection.
class ShareDelivered extends ShareEvent {
  final String receiverAddress;
  const ShareDelivered(this.receiverAddress);
}

/// Wrong PIN / unreachable peer / malformed payload, with a user-facing message.
class NearbyShareException implements Exception {
  final String message;
  final bool wrongPin;
  const NearbyShareException(this.message, {this.wrongPin = false});

  @override
  String toString() => message;
}
