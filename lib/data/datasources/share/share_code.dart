/// Short, typeable pairing code for nearby sharing: a private IPv4 address,
/// one of [ports], and the PIN, packed into 9 Crockford base32 characters
/// (shown as `K7Q-4MX-P2A`). Decoding is pure math — no server involved.
///
/// Layout (45 bits, most significant first):
///
///   range tag | host bits | port slot (2) | PIN (14) | check bits
///
/// The tag is a prefix code so the most common and widest range costs least:
///
///   `0`  + 24 bits  → 10.0.0.0/8
///   `10` + 16 bits  → 192.168.0.0/16
///   `11` + 20 bits  → 172.16.0.0/12
///
/// Whatever is left of the 45 bits (4, 11, or 7) is a checksum, so a mistyped
/// character is almost always reported as an invalid code rather than sending
/// the receiver to the wrong host.
class ShareCode {
  ShareCode._();

  /// Fixed share-server ports; the code stores which one was bound.
  static const List<int> ports = [47778, 47779, 47780, 47781];

  static const int length = 9;
  static const int _totalBits = 45;
  static const int _pinBits = 14;
  static const int _slotBits = 2;
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Prefix in QR payloads, so a scanned code is recognizably ours.
  static const String qrPrefix = 'arbiter-share:';

  /// Encodes, or returns null when [ipv4] isn't in a private range, [port]
  /// isn't one of [ports], or [pin] isn't 0000–9999.
  static String? encode({required String ipv4, required int port, required String pin}) {
    final ip = _parseIpv4(ipv4);
    final slot = ports.indexOf(port);
    final pinValue = int.tryParse(pin);
    if (ip == null || slot < 0 || pinValue == null || pin.length != 4) return null;

    final int tag, tagBits, host, hostBits;
    if (ip >> 24 == 10) {
      (tag, tagBits, host, hostBits) = (0, 1, ip & 0xFFFFFF, 24);
    } else if (ip >> 16 == 0xC0A8) {
      (tag, tagBits, host, hostBits) = (2, 2, ip & 0xFFFF, 16);
    } else if (ip >> 20 == 0xAC1) {
      (tag, tagBits, host, hostBits) = (3, 2, ip & 0xFFFFF, 20);
    } else {
      return null;
    }

    var payload = tag;
    payload = (payload << hostBits) | host;
    payload = (payload << _slotBits) | slot;
    payload = (payload << _pinBits) | pinValue;
    final checkBits = _totalBits - tagBits - hostBits - _slotBits - _pinBits;
    final value = (payload << checkBits) | _check(payload, checkBits);

    final chars = List.filled(length, '');
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      chars[i] = _alphabet[v & 31];
      v >>= 5;
    }
    return chars.join();
  }

  /// Decodes a typed or scanned code. Tolerates lowercase, spaces, dashes,
  /// the QR prefix, and Crockford look-alikes (O→0, I/L→1). Null if invalid.
  static ({String host, int port, String pin})? decode(String input) {
    var text = input.trim();
    if (text.toLowerCase().startsWith(qrPrefix)) text = text.substring(qrPrefix.length);
    text = text
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    if (text.length != length) return null;

    var value = 0;
    for (final ch in text.split('')) {
      final digit = _alphabet.indexOf(ch);
      if (digit < 0) return null;
      value = (value << 5) | digit;
    }

    final int hostBits, tagBits;
    final int base;
    if (value >> (_totalBits - 1) == 0) {
      (tagBits, hostBits, base) = (1, 24, 10 << 24);
    } else if (value >> (_totalBits - 2) == 2) {
      (tagBits, hostBits, base) = (2, 16, 0xC0A8 << 16);
    } else {
      (tagBits, hostBits, base) = (2, 20, 0xAC1 << 20);
    }
    final checkBits = _totalBits - tagBits - hostBits - _slotBits - _pinBits;
    final payload = value >> checkBits;
    if (_check(payload, checkBits) != value & ((1 << checkBits) - 1)) return null;

    final pinValue = payload & ((1 << _pinBits) - 1);
    final slot = (payload >> _pinBits) & ((1 << _slotBits) - 1);
    final host = (payload >> (_pinBits + _slotBits)) & ((1 << hostBits) - 1);
    if (pinValue > 9999) return null;
    final ip = base | host;
    return (
      host: '${(ip >> 24) & 255}.${(ip >> 16) & 255}.${(ip >> 8) & 255}.${ip & 255}',
      port: ports[slot],
      pin: pinValue.toString().padLeft(4, '0'),
    );
  }

  /// `K7Q4MXP2A` → `K7Q-4MX-P2A`.
  static String format(String code) =>
      '${code.substring(0, 3)}-${code.substring(3, 6)}-${code.substring(6)}';

  /// Picks the address to encode: the first one in a private range.
  static String? codeFor({required List<String> addresses, required int port, required String pin}) {
    for (final address in addresses) {
      final code = encode(ipv4: address, port: port, pin: pin);
      if (code != null) return code;
    }
    return null;
  }

  /// FNV-1a over the payload's bytes, folded to [bits]. Any mix works; it just
  /// has to change for small edits so single-character typos are caught.
  static int _check(int payload, int bits) {
    var hash = 0x811C9DC5;
    for (var shift = 40; shift >= 0; shift -= 8) {
      hash ^= (payload >> shift) & 0xFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return (hash ^ (hash >> 16)) & ((1 << bits) - 1);
  }

  static int? _parseIpv4(String address) {
    final parts = address.split('.');
    if (parts.length != 4) return null;
    var ip = 0;
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return null;
      ip = (ip << 8) | n;
    }
    return ip;
  }
}
