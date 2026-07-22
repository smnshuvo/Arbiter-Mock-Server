import 'dart:math';

/// Simulated mobile network conditions, applied per [Endpoint].
///
/// Naming note: this is deliberately *not* called `NetworkProfile` — in this
/// codebase "profile" already means an endpoint collection ([Profile]).
enum NetworkCondition {
  /// No simulation — the response is served as fast as the device allows.
  none,
  gprs,
  edge,
  threeG,
  fourG,
  fiveG,

  /// Deliberately flaky 2G: 2G-class speed plus random connection timeouts.
  unstable2G,
}

/// Bandwidth/latency characteristics of a [NetworkCondition].
///
/// The delay for a response is:
///   `latencyMs + random(0..jitterMs) + (bytes * 8 / kbps)`
/// i.e. a fixed round-trip cost plus the time to actually push the payload
/// down a link of the given bandwidth. That second term is what makes a large
/// body feel slow on GPRS but not on 5G.
class NetworkConditionSpec {
  const NetworkConditionSpec({
    required this.label,
    required this.description,
    required this.kbps,
    required this.latencyMs,
    this.jitterMs = 0,
    this.timeoutProbability = 0,
    this.timeoutAfterMs = 30000,
  });

  /// Short name shown in the picker.
  final String label;

  /// One-line summary shown under [label].
  final String description;

  /// Downlink bandwidth in kilobits per second.
  final int kbps;

  /// Base round-trip latency before any bytes flow.
  final int latencyMs;

  /// Upper bound of the random extra latency added per request.
  final int jitterMs;

  /// Chance in `[0, 1]` that a request times out instead of responding.
  final double timeoutProbability;

  /// How long a timed-out request hangs before failing with 504.
  final int timeoutAfterMs;

  bool get isUnstable => timeoutProbability > 0;

  /// Total time a [bytes]-sized response should take to arrive:
  /// latency + jitter + transfer time at [kbps].
  ///
  /// [random] is injectable so tests can pin the jitter.
  Duration delayFor(int bytes, {Random? random}) {
    if (kbps <= 0) return Duration.zero;
    final rng = random ?? _rng;
    final jitter = jitterMs > 0 ? rng.nextInt(jitterMs + 1) : 0;
    // bytes → bits → ms at kbps (bits per second / 1000).
    final transferMs = (bytes * 8) ~/ kbps;
    return Duration(milliseconds: latencyMs + jitter + transferMs);
  }

  /// Whether this particular request should be dropped as a timeout.
  /// Only ever true for unstable conditions.
  bool rollTimeout({Random? random}) {
    if (timeoutProbability <= 0) return false;
    return (random ?? _rng).nextDouble() < timeoutProbability;
  }
}

final Random _rng = Random();

/// Spec table. Values approximate the real-world throughput of each
/// generation rather than their theoretical maximums, which is what makes the
/// simulation feel like the real thing.
const Map<NetworkCondition, NetworkConditionSpec> kNetworkConditionSpecs = {
  NetworkCondition.none: NetworkConditionSpec(
    label: 'No throttling',
    description: 'Serve as fast as possible',
    kbps: 0, // 0 = unlimited; skips the transfer-time term
    latencyMs: 0,
  ),
  NetworkCondition.gprs: NetworkConditionSpec(
    label: 'GPRS',
    description: '50 kbps · 500 ms',
    kbps: 50,
    latencyMs: 500,
    jitterMs: 100,
  ),
  NetworkCondition.edge: NetworkConditionSpec(
    label: 'EDGE',
    description: '240 kbps · 300 ms',
    kbps: 240,
    latencyMs: 300,
    jitterMs: 80,
  ),
  NetworkCondition.threeG: NetworkConditionSpec(
    label: '3G',
    description: '1.6 Mbps · 150 ms',
    kbps: 1600,
    latencyMs: 150,
    jitterMs: 50,
  ),
  NetworkCondition.fourG: NetworkConditionSpec(
    label: '4G',
    description: '9 Mbps · 50 ms',
    kbps: 9000,
    latencyMs: 50,
    jitterMs: 20,
  ),
  NetworkCondition.fiveG: NetworkConditionSpec(
    label: '5G',
    description: '50 Mbps · 15 ms',
    kbps: 50000,
    latencyMs: 15,
    jitterMs: 5,
  ),
  NetworkCondition.unstable2G: NetworkConditionSpec(
    label: 'Unstable 2G',
    description: '40 kbps · 650 ms · ~25% time out',
    kbps: 40,
    latencyMs: 650,
    jitterMs: 400,
    timeoutProbability: 0.25,
    timeoutAfterMs: 30000,
  ),
};

extension NetworkConditionX on NetworkCondition {
  NetworkConditionSpec get spec => kNetworkConditionSpecs[this]!;

  String get label => spec.label;

  bool get isThrottled => this != NetworkCondition.none;

  /// Parses a persisted/imported name, falling back to [none] for unknown or
  /// missing values so old rows and foreign exports stay loadable.
  static NetworkCondition fromName(String? name) {
    if (name == null) return NetworkCondition.none;
    return NetworkCondition.values.firstWhere(
      (c) => c.name == name,
      orElse: () => NetworkCondition.none,
    );
  }
}
