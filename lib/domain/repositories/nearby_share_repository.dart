import '../entities/endpoint.dart';
import '../entities/nearby_share.dart';

/// Share a collection with, or receive one from, another Arbiter instance on
/// the same network. Sharing is opt-in and time-boxed: a sender is only
/// discoverable between [startSharing] and [stopSharing], and every download
/// must present the PIN it shows.
abstract class NearbyShareRepository {
  /// Starts advertising [endpoints] under [collectionName]. Replaces any share
  /// already in progress.
  Future<ShareSession> startSharing({
    required String collectionName,
    required List<Endpoint> endpoints,
  });

  Future<void> stopSharing();

  /// PIN rotations and deliveries for the active share.
  Stream<ShareEvent> get shareEvents;

  /// Emits the current list of sharing peers, refreshed while listened to.
  /// Cancelling the subscription stops searching.
  Stream<List<NearbyPeer>> discoverPeers();

  /// Looks up a sharing device by typed address, for networks where discovery
  /// is blocked. Throws [NearbyShareException].
  Future<NearbyPeer> connectTo(String host, int port);

  /// Downloads [peer]'s collection. Throws [NearbyShareException].
  Future<SharedCollection> fetchCollection(NearbyPeer peer, String pin);
}
