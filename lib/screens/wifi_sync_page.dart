import 'dart:async';

import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../database/peer_sync_stub.dart' if (dart.library.io) '../database/peer_sync_io.dart';
import '../database/peer_sync_protocol.dart';
import 'app_ui.dart';
import 'brand.dart';

/// Sync with another phone or a Windows PC over the same Wi-Fi or hotspot,
/// without internet. One device receives (host), the other connects.
class WifiSyncPage extends StatefulWidget {
  final AppDatabase database;
  final VoidCallback onChanged;

  const WifiSyncPage({super.key, required this.database, required this.onChanged});

  @override
  State<WifiSyncPage> createState() => _WifiSyncPageState();
}

class _WifiSyncPageState extends State<WifiSyncPage> {
  final PeerSyncHost _host = PeerSyncHost();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final List<String> _log = <String>[];

  PeerHostInfo? _info;
  bool _starting = false;
  bool _syncing = false;
  String? _progress;
  String? _result;
  String? _error;

  @override
  void dispose() {
    unawaited(_host.stop());
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, message);
      if (_log.length > 20) _log.removeLast();
    });
  }

  Future<void> _startHost() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final info = await _host.start(
        widget.database,
        onLog: _addLog,
        onDataChanged: () {
          if (mounted) widget.onChanged();
        },
      );
      if (!mounted) {
        await _host.stop();
        return;
      }
      setState(() => _info = info);
    } on PeerSyncException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stopHost() async {
    await _host.stop();
    if (mounted) setState(() => _info = null);
  }

  Future<void> _runSync() async {
    final raw = _address.text.trim();
    final code = _code.text.trim();
    if (raw.isEmpty || code.length != 6) {
      setState(() {
        _error = 'Enter the other device\'s address and its 6-digit code.';
        _result = null;
      });
      return;
    }
    var host = raw;
    var port = PeerSyncProtocol.defaultPort;
    final colon = raw.lastIndexOf(':');
    if (colon > 0) {
      host = raw.substring(0, colon);
      port = int.tryParse(raw.substring(colon + 1)) ?? port;
    }
    setState(() {
      _syncing = true;
      _error = null;
      _result = null;
      _progress = 'Starting...';
    });
    try {
      final r = await PeerSyncClient.sync(
        widget.database,
        host: host,
        port: port,
        code: code,
        onProgress: (m) {
          if (mounted) setState(() => _progress = m);
        },
      );
      widget.onChanged();
      if (!mounted) return;
      setState(() {
        _result = 'Done. Sent ${r.sent} change(s), received ${r.received} change(s)'
            '${r.failed > 0 ? ', ${r.failed} could not be applied yet (try again after syncing the other devices)' : ''}.';
      });
    } on PeerSyncException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Sync failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _progress = null;
        });
      }
    }
  }

  Widget _card(String title, IconData icon, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(icon, color: kBrandGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kBrandGreen)),
                ),
              ]),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi Sync (Nearby Devices)')),
      body: IslamicBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!PeerSyncHost.supported)
              _card('Not available on the web', Icons.info_outline, const [
                Text('A browser cannot connect directly to another device. Use the normal Firebase sync here, '
                    'or use the Android or Windows app for Wi-Fi sync.'),
              ])
            else ...[
              _card('How it works', Icons.wifi_tethering, const [
                Text(
                  'Syncs two devices directly, without internet. Put both on the same Wi-Fi, or switch on a phone hotspot '
                  'and connect the other device to it. Works Android to Android and Windows to Android.\n\n'
                  'On one device tap START RECEIVING. On the other device enter the address and code shown, then tap SYNC NOW. '
                  'Changes are merged with the same rules as cloud sync, so syncing with Firebase later will not duplicate anything. '
                  'With three or more devices, sync each pair.',
                  style: TextStyle(height: 1.35),
                ),
                SizedBox(height: 8),
                Text(
                  'Use only a Wi-Fi or hotspot you control. Devices prove they know the code, but data is not encrypted on the network.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ]),
              _card('1. Receive (this device is the host)', Icons.download_for_offline_outlined, [
                if (info == null)
                  FilledButton.icon(
                    onPressed: _starting ? null : _startHost,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(_starting ? 'STARTING...' : 'START RECEIVING'),
                  )
                else ...[
                  const Text('Receiving. On the other device enter:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  SelectableText(
                    info.addresses.isEmpty
                        ? 'Address: (not found - check Wi-Fi)'
                        : info.addresses.map((a) => '$a:${info.port}').join('\n'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text('Code', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  SelectableText(
                    info.code,
                    style: const TextStyle(fontSize: 30, letterSpacing: 6, fontWeight: FontWeight.w900, color: kBrandGreen),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _stopHost,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('STOP RECEIVING'),
                  ),
                  if (_log.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final line in _log.take(6)) Text('\u2022 $line', style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ]),
              _card('2. Connect to a host', Icons.sync_alt_rounded, [
                TextField(
                  controller: _address,
                  enabled: !_syncing,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Host address (e.g. 192.168.43.1:8765)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _code,
                  enabled: !_syncing,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: '6-digit code', border: OutlineInputBorder(), counterText: ''),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _syncing ? null : _runSync,
                  icon: _syncing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync_rounded),
                  label: Text(_syncing ? 'SYNCING...' : 'SYNC NOW'),
                ),
                if (_progress != null) ...[
                  const SizedBox(height: 8),
                  Text(_progress!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ]),
            ],
            if (_result != null)
              Card(
                color: Colors.green.shade50,
                child: Padding(padding: const EdgeInsets.all(12), child: Text(_result!)),
              ),
            if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: Colors.red.shade900))),
              ),
          ],
        ),
      ),
    );
  }
}
