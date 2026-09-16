import 'dart:math';

import 'package:arbiter_mock_server/data/datasources/share/share_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips every private range, port slot and PIN edge', () {
    const addresses = [
      '10.21.178.27', '10.0.0.0', '10.255.255.255',
      '192.168.1.20', '192.168.255.255',
      '172.16.0.1', '172.31.255.254',
    ];
    for (final ip in addresses) {
      for (final port in ShareCode.ports) {
        for (final pin in ['0000', '0420', '9999']) {
          final code = ShareCode.encode(ipv4: ip, port: port, pin: pin);
          expect(code, hasLength(ShareCode.length), reason: '$ip:$port/$pin');
          expect(ShareCode.decode(code!), (host: ip, port: port, pin: pin));
        }
      }
    }
  });

  test('refuses what it cannot represent', () {
    expect(ShareCode.encode(ipv4: '8.8.8.8', port: 47778, pin: '1234'), isNull);
    expect(ShareCode.encode(ipv4: '172.32.0.1', port: 47778, pin: '1234'), isNull);
    expect(ShareCode.encode(ipv4: '10.0.0.1', port: 8080, pin: '1234'), isNull);
    expect(ShareCode.encode(ipv4: '10.0.0.1', port: 47778, pin: '12345'), isNull);
  });

  test('tolerant input: case, dashes, spaces, QR prefix, look-alikes', () {
    final code = ShareCode.encode(ipv4: '10.21.113.63', port: 47779, pin: '0101')!;
    final expected = (host: '10.21.113.63', port: 47779, pin: '0101');
    expect(ShareCode.decode(' ${ShareCode.format(code).toLowerCase()} '), expected);
    expect(ShareCode.decode('${ShareCode.qrPrefix}$code'), expected);
    expect(ShareCode.decode(code.replaceAll('0', 'O').replaceAll('1', 'I')), expected);
  });

  test('most single-character typos are rejected', () {
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final random = Random(7);
    var caught = 0, total = 0;
    for (var n = 0; n < 300; n++) {
      final ip = '10.${random.nextInt(256)}.${random.nextInt(256)}.${random.nextInt(256)}';
      final code = ShareCode.encode(
          ipv4: ip, port: ShareCode.ports[random.nextInt(4)], pin: '${random.nextInt(10000)}'.padLeft(4, '0'))!;
      final i = random.nextInt(code.length);
      final replacement = alphabet[random.nextInt(alphabet.length)];
      if (replacement == code[i]) continue;
      total++;
      final typo = code.replaceRange(i, i + 1, replacement);
      if (ShareCode.decode(typo) == null) caught++;
    }
    // 10.x codes carry the fewest check bits (4), so expect ~15/16 caught.
    expect(caught / total, greaterThan(0.85));
  });

  test('garbage decodes to null', () {
    expect(ShareCode.decode(''), isNull);
    expect(ShareCode.decode('ABC'), isNull);
    expect(ShareCode.decode('UUUUUUUUU'), isNull);
  });
}
