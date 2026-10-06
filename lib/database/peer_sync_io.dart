import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'app_database.dart';
import 'peer_sync_protocol.dart';

/// Native (Android / Windows) implementation of nearby-device sync.
///
/// One device hosts a small HTTP server on the local network; the other device
/// connects with the host's address and the six-digit code. Every request and
/// every reply is signed with HMAC-SHA256 using the code, so neither side
/// accepts data from a device that does not know it.
class PeerSyncHost {
  static const bool supported = true;
  static const int _maxBodyBytes = 24 * 1024 * 1024;
  static const int _maxFailures = 8;

  HttpServer? _server;
  AppDatabase? _db;
  String _code = '';
  int _failures = 0;
  void Function(String message)? _onLog;
  void Function()? _onDataChanged;

  bool get running => _server != null;

  Future<PeerHostInfo> start(
    AppDatabase db, {
    int port = PeerSyncProtocol.defaultPort,
    void Function(String message)? onLog,
    void Function()? onDataChanged,
  }) async {
    await stop();
    _db = db;
    _onLog = onLog;
    _onDataChanged = onDataChanged;
    _code = PeerSyncProtocol.newPairingCode();
    _failures = 0;
    final HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    } on SocketException catch (e) {
      throw PeerSyncException(
        'Could not start receiving on port $port. Another program may be using it, '
        'or the firewall blocked it. (${e.message})',
      );
    }
    _server = server;
    server.listen(
      _handle,
      onError: (Object e) => _onLog?.call('Server error: $e'),
      cancelOnError: false,
    );
    final addresses = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final address in iface.addresses) {
          addresses.add(address.address);
        }
      }
    } catch (_) {
      // The address list is only a convenience for the user.
    }
    return PeerHostInfo(addresses: addresses, port: server.port, code: _code);
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _db = null;
    _code = '';
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _reply(
    HttpResponse response,
    int status,
    Map<String, dynamic> body, {
    bool signed = false,
  }) async {
    final text = jsonEncode(body);
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    if (signed && _code.isNotEmpty) {
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      response.headers.set('x-aabm-ts', ts);
      response.headers.set('x-aabm-sig', PeerSyncProtocol.sign(_code, ts, text));
    }
    response.write(text);
    await response.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final db = _db;
      if (db == null || _code.isEmpty) {
        await _reply(response, 503, {'error': 'Not receiving.'});
        return;
      }
      if (_failures >= _maxFailures) {
        await _reply(response, 429, {
          'error': 'Too many wrong attempts. Stop and start receiving again to get a new code.',
        });
        return;
      }
      if (request.method != 'POST') {
        await _reply(response, 405, {'error': 'Use POST.'});
        return;
      }
      final builder = BytesBuilder(copy: false);
      var tooLarge = false;
      await for (final chunk in request) {
        builder.add(chunk);
        if (builder.length > _maxBodyBytes) {
          tooLarge = true;
          break;
        }
      }
      if (tooLarge) {
        await _reply(response, 413, {'error': 'Request too large.'});
        return;
      }
      final body = utf8.decode(builder.takeBytes());
      final ts = request.headers.value('x-aabm-ts') ?? '';
      final sig = request.headers.value('x-aabm-sig') ?? '';
      if (!PeerSyncProtocol.verify(_code, ts, body, sig)) {
        _failures++;
        _onLog?.call('A device with a wrong code or wrong clock tried to connect.');
        await _reply(response, 401, {
          'error': 'Wrong code, or the two device clocks differ by more than 10 minutes.',
        });
        return;
      }
      final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
      final payload = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
      switch (request.uri.path) {
        case '/hello':
          await _reply(response, 200, await PeerSyncProtocol.hello(db), signed: true);
        case '/sync':
          final result = await PeerSyncProtocol.handleSync(db, payload);
          _onLog?.call(
            'Exchanged with a device: received ${result['applied']} change(s), '
            'sent ${(result['changes'] as List).length}.',
          );
          _onDataChanged?.call();
          await _reply(response, 200, result, signed: true);
        default:
          await _reply(response, 404, {'error': 'Unknown request.'});
      }
    } on PeerSyncException catch (e) {
      _onLog?.call(e.message);
      try {
        await _reply(response, 409, {'error': e.message});
      } catch (_) {
        // The connection was already closed.
      }
    } catch (e) {
      _onLog?.call('Request failed: $e');
      try {
        await _reply(response, 500, {'error': 'The host could not process the request.'});
      } catch (_) {
        // The connection was already closed.
      }
    }
  }
}

class PeerSyncClient {
  static Future<PeerSyncResult> sync(
    AppDatabase db, {
    required String host,
    required int port,
    required String code,
    void Function(String message)? onProgress,
  }) {
    return PeerSyncProtocol.runClient(
      db,
      onProgress: onProgress,
      post: (path, body) => _post(host, port, code, path, body),
    );
  }

  static Future<Map<String, dynamic>> _post(
    String host,
    int port,
    String code,
    String path,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final text = jsonEncode(body);
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      final request = await client
          .postUrl(Uri(scheme: 'http', host: host, port: port, path: path))
          .timeout(const Duration(seconds: 10));
      final bytes = utf8.encode(text);
      request.headers.contentType = ContentType.json;
      request.headers.set('x-aabm-ts', ts);
      request.headers.set('x-aabm-sig', PeerSyncProtocol.sign(code, ts, text));
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(const Duration(seconds: 90));
      final responseText = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        String message = 'The other device answered with error ${response.statusCode}.';
        try {
          final err = jsonDecode(responseText);
          if (err is Map && err['error'] != null) message = err['error'].toString();
        } catch (_) {
          // Keep the generic message.
        }
        throw PeerSyncException(message);
      }
      final rts = response.headers.value('x-aabm-ts') ?? '';
      final rsig = response.headers.value('x-aabm-sig') ?? '';
      if (!PeerSyncProtocol.verify(code, rts, responseText, rsig)) {
        throw const PeerSyncException(
          'The other device could not prove it knows the code. Nothing was changed.',
        );
      }
      final decoded = jsonDecode(responseText);
      if (decoded is! Map) {
        throw const PeerSyncException('The other device sent an unreadable reply.');
      }
      return Map<String, dynamic>.from(decoded);
    } on TimeoutException {
      throw PeerSyncException(
        'The other device at $host:$port did not answer in time. '
        'Check that it is receiving and on the same Wi-Fi or hotspot.',
      );
    } on SocketException {
      throw PeerSyncException(
        'Cannot reach $host:$port. Both devices must be on the same Wi-Fi or hotspot, '
        'and the other device must be showing "Receiving".',
      );
    } finally {
      client.close(force: true);
    }
  }
}
