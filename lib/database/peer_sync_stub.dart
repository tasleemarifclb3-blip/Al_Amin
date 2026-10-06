import 'app_database.dart';
import 'peer_sync_protocol.dart';

/// Web build: a browser cannot open a local server or raw sockets, so nearby
/// device sync is unavailable there. Use Firebase sync on the web.
class PeerSyncHost {
  static const bool supported = false;

  bool get running => false;

  Future<PeerHostInfo> start(
    AppDatabase db, {
    int port = PeerSyncProtocol.defaultPort,
    void Function(String message)? onLog,
    void Function()? onDataChanged,
  }) async {
    throw const PeerSyncException('Wi-Fi sync is not available in the web version.');
  }

  Future<void> stop() async {}
}

class PeerSyncClient {
  static Future<PeerSyncResult> sync(
    AppDatabase db, {
    required String host,
    required int port,
    required String code,
    void Function(String message)? onProgress,
  }) async {
    throw const PeerSyncException('Wi-Fi sync is not available in the web version.');
  }
}
