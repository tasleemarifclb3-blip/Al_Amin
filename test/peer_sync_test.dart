import 'package:al_amin/database/peer_sync_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PeerSyncProtocol', () {
    String now() => DateTime.now().millisecondsSinceEpoch.toString();

    test('pairing code has six digits', () {
      for (var i = 0; i < 20; i++) {
        expect(RegExp(r'^\d{6}$').hasMatch(PeerSyncProtocol.newPairingCode()), isTrue);
      }
    });

    test('a correctly signed message verifies', () {
      final ts = now();
      final sig = PeerSyncProtocol.sign('123456', ts, '{"a":1}');
      expect(PeerSyncProtocol.verify('123456', ts, '{"a":1}', sig), isTrue);
    });

    test('wrong code, changed body or bad signature is rejected', () {
      final ts = now();
      final sig = PeerSyncProtocol.sign('123456', ts, '{"a":1}');
      expect(PeerSyncProtocol.verify('654321', ts, '{"a":1}', sig), isFalse);
      expect(PeerSyncProtocol.verify('123456', ts, '{"a":2}', sig), isFalse);
      expect(PeerSyncProtocol.verify('123456', ts, '{"a":1}', 'abc'), isFalse);
    });

    test('an old timestamp is rejected', () {
      final old = DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch.toString();
      final sig = PeerSyncProtocol.sign('123456', old, 'x');
      expect(PeerSyncProtocol.verify('123456', old, 'x', sig), isFalse);
      expect(PeerSyncProtocol.verify('123456', 'not-a-number', 'x', sig), isFalse);
    });

    test('constantTimeEquals compares exactly', () {
      expect(PeerSyncProtocol.constantTimeEquals('abc', 'abc'), isTrue);
      expect(PeerSyncProtocol.constantTimeEquals('abc', 'abd'), isFalse);
      expect(PeerSyncProtocol.constantTimeEquals('abc', 'abcd'), isFalse);
    });
  });
}
