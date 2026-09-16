import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:uuid/uuid.dart';

import '../../../domain/entities/endpoint.dart';
import '../../../domain/entities/nearby_share.dart';
import '../../../domain/repositories/nearby_share_repository.dart';
import 'nearby_share_protocol.dart';
import 'share_code.dart';

/// LAN implementation of [NearbyShareRepository]: UDP broadcast discovery
/// plus a short-lived HTTP server for the transfer.
///
/// The share server is deliberately separate from the mock servers — it
/// exists only while a share dialog is open, never goes through interception
/// or logging, and can't be shadowed by a user's own endpoint.
class NearbyShareService implements NearbyShareRepository {
  NearbyShareService({
    this.discoveryPort = NearbyShareProtocol.discoveryPort,
    this.peerTtl = const Duration(seconds: 7),
    this.probeInterval = const Duration(seconds: 2),
    this.sharePorts = ShareCode.ports,
  });

  /// Overridable so tests don't collide with a running app.
  final int discoveryPort;
  final Duration peerTtl;
  final Duration probeInterval;

  /// Tried in order for the share server; a short code can only be issued on
  /// one of [ShareCode.ports]. Falls back to an OS-assigned port (address-only
  /// sharing) if all are taken.
  final List<int> sharePorts;

  HttpServer? _httpServer;
  RawDatagramSocket? _advertSocket;
  String _pin = '';
  int _failedAttempts = 0;
  List<String> _addresses = const [];
  final StreamController<ShareEvent> _events = StreamController.broadcast();

  static String get deviceName {
    final host = Platform.localHostname.replaceAll(RegExp(r'\.local$'), '');
    if (host.isNotEmpty && host != 'localhost') return host;
    if (Platform.isAndroid) return 'Android device';
    if (Platform.isIOS) return 'iPhone / iPad';
    return Platform.operatingSystem;
  }

  @override
  Stream<ShareEvent> get shareEvents => _events.stream;

  /// Port of the active share server — exposed for tests.
  int? get sharePort => _httpServer?.port;

  @override
  Future<ShareSession> startSharing({
    required String collectionName,
    required List<Endpoint> endpoints,
  }) async {
    await stopSharing();
    _pin = NearbyShareProtocol.generatePin();
    _failedAttempts = 0;
    final sessionId = const Uuid().v4();
    final device = deviceName;
    final payload = NearbyShareProtocol.encodeCollection(
      deviceName: device,
      collectionName: collectionName,
      endpoints: endpoints,
    );

    late final List<int> offer;
    Future<Response> handler(Request request) => _handleTransfer(request, payload, offer);
    HttpServer? bound;
    for (final port in [...sharePorts, 0]) {
      try {
        bound = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
        break;
      } on SocketException {
        // Taken (e.g. another Arbiter sharing on this machine) — try the next.
      }
    }
    if (bound == null) {
      throw const NearbyShareException('Could not open a port for sharing.');
    }
    final server = bound;
    _httpServer = server;
    offer = NearbyShareProtocol.offer(
      sessionId: sessionId,
      deviceName: device,
      collectionName: collectionName,
      endpointCount: endpoints.length,
      port: server.port,
    );

    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        // Lets two instances on one machine both share. Unsupported (throws)
        // on Windows and Android.
        reusePort: Platform.isMacOS || Platform.isIOS || Platform.isLinux,
      );
      _joinMulticast(socket, await _ipv4Interfaces());
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null || !NearbyShareProtocol.isDiscoveryRequest(datagram.data)) return;
        socket.send(offer, datagram.address, datagram.port);
      });
      _advertSocket = socket;
    } on SocketException catch (e) {
      await stopSharing();
      throw NearbyShareException(
          'Could not listen for nearby devices (${e.osError?.message ?? e.message}).');
    }
    _addresses = [
      for (final iface in await _ipv4Interfaces())
        for (final addr in iface.addresses)
          if (!addr.isLoopback && !addr.isLinkLocal) addr.address,
    ];
    return _session();
  }

  ShareSession _session() {
    final port = _httpServer?.port ?? 0;
    return ShareSession(
      pin: _pin,
      port: port,
      addresses: _addresses,
      code: ShareCode.codeFor(addresses: _addresses, port: port, pin: _pin),
    );
  }

  /// Best effort: join on the default interface and each IPv4 one, so the
  /// group is heard whichever interface the receiver's packet arrives on.
  void _joinMulticast(RawDatagramSocket socket, List<NetworkInterface> interfaces) {
    final group = InternetAddress(NearbyShareProtocol.multicastGroup);
    for (final iface in <NetworkInterface?>[null, ...interfaces]) {
      try {
        socket.joinMulticast(group, iface);
      } catch (_) {
        // Already joined / multicast unavailable here — broadcast still works.
      }
    }
  }

  Future<List<NetworkInterface>> _ipv4Interfaces() async {
    try {
      return await NetworkInterface.list(type: InternetAddressType.IPv4);
    } catch (_) {
      return const [];
    }
  }

  Future<Response> _handleTransfer(Request request, String payload, List<int> offer) async {
    final path = '/${request.url.path}';
    if (request.method == 'GET' && path == NearbyShareProtocol.infoPath) {
      // No PIN: only what discovery already announces to the whole network.
      return Response.ok(offer, headers: {'content-type': 'application/json'});
    }
    if (request.method != 'GET' || path != NearbyShareProtocol.collectionPath) {
      return Response.notFound('');
    }
    final given = request.headers[NearbyShareProtocol.pinHeader];
    if (!NearbyShareProtocol.pinMatches(_pin, given)) {
      _failedAttempts++;
      if (_failedAttempts >= NearbyShareProtocol.maxPinAttempts) {
        // Stop brute force: 5 guesses out of 10,000, then the PIN changes.
        _pin = NearbyShareProtocol.generatePin();
        _failedAttempts = 0;
        _events.add(SharePinRotated(_session()));
      }
      return Response(401, body: 'Wrong PIN');
    }
    final info = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    _events.add(ShareDelivered(info?.remoteAddress.address ?? 'unknown'));
    return Response.ok(payload, headers: {'content-type': 'application/json'});
  }

  @override
  Future<void> stopSharing() async {
    _advertSocket?.close();
    _advertSocket = null;
    await _httpServer?.close(force: true);
    _httpServer = null;
  }

  @override
  Stream<List<NearbyPeer>> discoverPeers() {
    RawDatagramSocket? socket;
    Timer? timer;
    var cancelled = false;
    final seen = <String, ({NearbyPeer peer, DateTime at})>{};
    late final StreamController<List<NearbyPeer>> controller;

    void emit() {
      if (!controller.isClosed) {
        controller.add([for (final entry in seen.values) entry.peer]);
      }
    }

    Future<void> probe() async {
      final s = socket;
      if (s == null) return;
      final now = DateTime.now();
      final before = seen.length;
      seen.removeWhere((_, v) => now.difference(v.at) > peerTtl);
      if (seen.length != before) emit();
      final request = NearbyShareProtocol.discoveryRequest();
      for (final target in await _broadcastTargets()) {
        try {
          s.send(request, target, discoveryPort);
        } catch (_) {
          // Unroutable target on this network — the others still go out.
        }
      }
    }

    controller = StreamController<List<NearbyPeer>>(
      onListen: () async {
        try {
          final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
          if (cancelled) {
            s.close(); // listener went away while binding
            return;
          }
          s.broadcastEnabled = true;
          s.listen((event) {
            if (event != RawSocketEvent.read) return;
            final datagram = s.receive();
            if (datagram == null) return;
            final peer = NearbyShareProtocol.parseOffer(datagram.data, datagram.address.address);
            if (peer == null) return;
            final existing = seen[peer.sessionId];
            // Same sender heard on loopback and on Wi-Fi: keep the LAN address.
            final keep = existing != null && peer.host == '127.0.0.1' ? existing.peer : peer;
            seen[peer.sessionId] = (peer: keep, at: DateTime.now());
            if (existing?.peer != keep) emit();
          });
          socket = s;
          emit();
          await probe();
          if (!cancelled) timer = Timer.periodic(probeInterval, (_) => probe());
        } catch (e) {
          controller.addError(NearbyShareException('Could not search the network: $e'));
        }
      },
      onCancel: () {
        cancelled = true;
        timer?.cancel();
        socket?.close();
        socket = null;
      },
    );
    return controller.stream;
  }

  /// Limited broadcast, directed-broadcast candidates per interface (macOS
  /// only sends 255.255.255.255 out of the primary interface), the multicast
  /// group, and loopback so two instances on the same machine find each other.
  Future<List<InternetAddress>> _broadcastTargets() async {
    final targets = <String>{
      '255.255.255.255',
      NearbyShareProtocol.multicastGroup,
      '127.0.0.1',
    };
    for (final iface in await _ipv4Interfaces()) {
      for (final addr in iface.addresses) {
        if (addr.isLoopback || addr.isLinkLocal) continue;
        targets.addAll(NearbyShareProtocol.broadcastCandidates(addr.address));
      }
    }
    return [for (final t in targets) InternetAddress(t)];
  }

  @override
  Future<NearbyPeer> connectTo(String host, int port) async {
    final uri = Uri(scheme: 'http', host: host, port: port, path: NearbyShareProtocol.infoPath);
    final http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 6));
    } catch (_) {
      throw NearbyShareException(
          "Couldn't reach $host:$port. Check the address, and that both devices are on the "
          'same network and the other one is still sharing.');
    }
    final peer = response.statusCode == 200
        ? NearbyShareProtocol.parseOffer(response.bodyBytes, host)
        : null;
    if (peer == null) {
      throw NearbyShareException('$host:$port is not an Arbiter device that is sharing.');
    }
    return peer;
  }

  @override
  Future<SharedCollection> fetchCollection(NearbyPeer peer, String pin) async {
    final uri = Uri(
      scheme: 'http',
      host: peer.host,
      port: peer.port,
      path: NearbyShareProtocol.collectionPath,
    );
    final http.Response response;
    try {
      response = await http
          .get(uri, headers: {NearbyShareProtocol.pinHeader: pin.trim()})
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      throw NearbyShareException(
          "Couldn't reach ${peer.deviceName}. Make sure it's still sharing and on the same Wi-Fi.");
    }
    if (response.statusCode == 401) {
      throw const NearbyShareException('Wrong PIN — check the code on the sharing device.',
          wrongPin: true);
    }
    if (response.statusCode != 200) {
      throw NearbyShareException('${peer.deviceName} stopped sharing (HTTP ${response.statusCode}).');
    }
    return NearbyShareProtocol.decodeCollection(response.body);
  }
}
