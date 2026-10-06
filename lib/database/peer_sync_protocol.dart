import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../domain/reset_epoch.dart';
import 'app_database.dart';
import 'sync_firestore_service.dart';
import 'sync_foundation.dart';

/// Error shown to the user when nearby-device sync cannot continue.
class PeerSyncException implements Exception {
  final String message;
  const PeerSyncException(this.message);

  @override
  String toString() => message;
}

/// What the host shows so another device can connect.
class PeerHostInfo {
  final List<String> addresses;
  final int port;
  final String code;
  const PeerHostInfo({required this.addresses, required this.port, required this.code});
}

class PeerSyncResult {
  final String peerDeviceId;
  final int sent;
  final int received;
  final int failed;
  const PeerSyncResult({
    required this.peerDeviceId,
    required this.sent,
    required this.received,
    required this.failed,
  });
}

class PeerApplyOutcome {
  final int applied;
  final int failed;

  /// Highest change sequence applied before the first failure (null if none).
  final int? lastContiguousSeq;
  const PeerApplyOutcome(this.applied, this.failed, this.lastContiguousSeq);
}

/// Transport-independent rules for syncing two devices directly over a local
/// network. The exchange reuses the Firestore change format and the same apply
/// code, so a change that arrives here and later arrives from Firestore is
/// recognised as a duplicate and applied only once.
class PeerSyncProtocol {
  PeerSyncProtocol._();

  static const int version = 1;
  static const int batchSize = 200;
  static const int defaultPort = 8765;
  static const Duration maxClockSkew = Duration(minutes: 10);

  /// Six-digit one-time code shown on the host device.
  static String newPairingCode() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

  static String sign(String code, String timestamp, String body) {
    final hmac = Hmac(sha256, utf8.encode(code));
    return hmac.convert(utf8.encode('$timestamp.$body')).toString();
  }

  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static bool verify(String code, String timestamp, String body, String signature) {
    final t = int.tryParse(timestamp);
    if (t == null) return false;
    final skew = (DateTime.now().millisecondsSinceEpoch - t).abs();
    if (skew > maxClockSkew.inMilliseconds) return false;
    return constantTimeEquals(sign(code, timestamp, body), signature);
  }

  static int _asInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    return int.tryParse('${value ?? ''}') ?? fallback;
  }

  static Future<Map<String, dynamic>> hello(AppDatabase db) async {
    return <String, dynamic>{
      'deviceId': await SyncFoundation.getDeviceId(db),
      'protocol': version,
      'resetToken': await SyncFoundation.getState(db, 'global_reset_token') ?? '',
    };
  }

  /// Both devices must be on the same database generation (same last global
  /// reset). Otherwise one of them still holds data that was deleted.
  static Future<void> requireSameGeneration(AppDatabase db, Object? peerToken) async {
    final own = await SyncFoundation.getState(db, 'global_reset_token') ?? '';
    if (!ResetEpoch.sameGeneration(own, (peerToken ?? '').toString())) {
      throw const PeerSyncException(
        'These two devices are on different database versions because one of them has not yet applied '
        'a global delete. Connect that device to the internet first so it can synchronize, then try again.',
      );
    }
  }

  /// Applies [changes] in order. Cursor progress stops at the first failure so
  /// the failed change and everything after it is sent again next time.
  static Future<PeerApplyOutcome> applyChanges(AppDatabase db, List<dynamic> changes) async {
    var applied = 0;
    var failed = 0;
    var contiguous = true;
    int? lastSeq;
    for (final raw in changes) {
      if (raw is! Map) {
        failed++;
        contiguous = false;
        continue;
      }
      final data = Map<String, dynamic>.from(raw);
      final seq = data['seq'] == null ? null : _asInt(data['seq'], -1);
      try {
        await SyncFirestoreService.applyPeerChange(db, data);
        applied++;
        if (contiguous && seq != null && seq >= 0) lastSeq = seq;
      } catch (_) {
        failed++;
        contiguous = false;
      }
    }
    return PeerApplyOutcome(applied, failed, lastSeq);
  }

  /// Host side of one exchange: apply what the client sent, then answer with
  /// this device's own changes after the client's cursor.
  static Future<Map<String, dynamic>> handleSync(
    AppDatabase db,
    Map<String, dynamic> request,
  ) async {
    await requireSameGeneration(db, request['resetToken']);
    final since = _asInt(request['since']);
    final incoming = request['changes'];
    final outcome = await applyChanges(db, incoming is List ? incoming : const <dynamic>[]);
    final mine = await SyncFoundation.getOwnChangesAfter(
      db,
      afterId: since,
      limit: batchSize + 1,
    );
    final hasMore = mine.length > batchSize;
    if (hasMore) mine.removeLast();
    return <String, dynamic>{
      'deviceId': await SyncFoundation.getDeviceId(db),
      'protocol': version,
      'applied': outcome.applied,
      'failed': outcome.failed,
      'ackOut': outcome.lastContiguousSeq,
      'changes': mine,
      'hasMore': hasMore,
    };
  }

  static String outCursorKey(String peerId) => 'peer_out:$peerId';
  static String inCursorKey(String peerId) => 'peer_in:$peerId';

  static Future<int> readCursor(AppDatabase db, String key) async {
    return int.tryParse(await SyncFoundation.getState(db, key) ?? '') ?? 0;
  }

  /// Client side: runs the exchange using [post] (the transport) until both
  /// devices have sent everything. Cursors are saved after every round.
  static Future<PeerSyncResult> runClient(
    AppDatabase db, {
    required Future<Map<String, dynamic>> Function(String path, Map<String, dynamic> body) post,
    void Function(String message)? onProgress,
  }) async {
    final ownId = await SyncFoundation.getDeviceId(db);
    onProgress?.call('Contacting the other device...');
    final hello = await post('/hello', <String, dynamic>{'deviceId': ownId});
    await requireSameGeneration(db, hello['resetToken']);
    final peerId = (hello['deviceId'] ?? '').toString();
    if (peerId.isEmpty) {
      throw const PeerSyncException('The other device did not identify itself.');
    }
    if (peerId == ownId) {
      throw const PeerSyncException('You connected to this same device.');
    }
    var outCursor = await readCursor(db, outCursorKey(peerId));
    var inCursor = await readCursor(db, inCursorKey(peerId));
    var sent = 0;
    var received = 0;
    var failed = 0;

    for (var round = 0; round < 500; round++) {
      final outgoing = await SyncFoundation.getOwnChangesAfter(
        db,
        afterId: outCursor,
        limit: batchSize,
      );
      onProgress?.call('Exchanging changes (round ${round + 1})...');
      final reply = await post('/sync', <String, dynamic>{
        'deviceId': ownId,
        'resetToken': await SyncFoundation.getState(db, 'global_reset_token') ?? '',
        'since': inCursor,
        'changes': outgoing,
      });

      final peerFailed = _asInt(reply['failed']);
      if (outgoing.isNotEmpty) {
        if (peerFailed == 0) {
          outCursor = _asInt(outgoing.last['seq'], outCursor);
        } else if (reply['ackOut'] != null) {
          outCursor = _asInt(reply['ackOut'], outCursor);
        }
        sent += outgoing.length - peerFailed;
        failed += peerFailed;
        await SyncFoundation.setState(db, outCursorKey(peerId), '$outCursor');
      }

      final incoming = reply['changes'] is List ? reply['changes'] as List : const <dynamic>[];
      final outcome = await applyChanges(db, incoming);
      received += outcome.applied;
      failed += outcome.failed;
      if (incoming.isNotEmpty) {
        if (outcome.failed == 0) {
          final last = incoming.last;
          inCursor = last is Map ? _asInt(last['seq'], inCursor) : inCursor;
        } else if (outcome.lastContiguousSeq != null) {
          inCursor = outcome.lastContiguousSeq!;
        }
        await SyncFoundation.setState(db, inCursorKey(peerId), '$inCursor');
      }

      final moreOut = outgoing.length >= batchSize;
      final moreIn = reply['hasMore'] == true;
      if (!moreOut && !moreIn) break;
      // A failed change blocks cursor progress; stop instead of looping.
      if (peerFailed > 0 || outcome.failed > 0) break;
    }
    return PeerSyncResult(
      peerDeviceId: peerId,
      sent: sent,
      received: received,
      failed: failed,
    );
  }
}
