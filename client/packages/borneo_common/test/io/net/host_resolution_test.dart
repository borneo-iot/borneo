import 'dart:io';

import 'package:borneo_common/io/net/host_resolution.dart';
import 'package:test/test.dart';

void main() {
  group('host resolution', () {
    test('keeps literal IPv4 hosts unchanged', () async {
      final resolved = await resolveHostToPreferredAddress('192.168.1.10');
      expect(resolved, '192.168.1.10');
    });

    test('prefers IPv4 over IPv6 results', () async {
      final resolved = await resolveHostToPreferredAddress(
        'borneo.local',
        lookup: (host, {type = InternetAddressType.any}) async => [
          InternetAddress('fe80::1234'),
          InternetAddress('192.168.10.20'),
          InternetAddress('2001:db8::1'),
        ],
      );

      expect(resolved, '192.168.10.20');
    });

    test('prefers non-link-local IPv6 when IPv4 is unavailable', () async {
      final selected = selectPreferredInternetAddress([InternetAddress('fe80::1234'), InternetAddress('2001:db8::10')]);

      expect(selected?.address, '2001:db8::10');
    });

    test('replaces uri hostname while preserving other parts', () async {
      final resolved = await resolveUriHostToPreferredAddress(
        Uri.parse('coap://borneo.local:5683/borneo/lyfi/info?mode=1'),
        lookup: (host, {type = InternetAddressType.any}) async => [InternetAddress('192.168.2.15')],
      );

      expect(resolved.scheme, 'coap');
      expect(resolved.host, '192.168.2.15');
      expect(resolved.port, 5683);
      expect(resolved.path, '/borneo/lyfi/info');
      expect(resolved.query, 'mode=1');
    });
  });
}
