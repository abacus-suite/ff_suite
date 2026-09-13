import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/offline_queue.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/warm_up.dart';

/// What the phone still has to send, and anything the server refused.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  List<QueuedRequest> _items = [];
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await Services.outbox.list();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await Services.outbox.flush();
      await Services.tracker.flush();
      if (mounted) {
        showSnack(context, Services.api.online.value ? 'Synced what could be sent' : 'Still offline');
      }
      Services.refresh.value++;
    } finally {
      await _reload();
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _discard(QueuedRequest item) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this?'),
        content: Text('"${item.label}" will not reach the office. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    if (sure != true) return;
    await Services.outbox.discard(item.uuid);
    await _reload();
  }

  String _when(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.day}/${local.month} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final failed = _items.where((i) => i.error != null).toList();
    final waiting = _items.where((i) => i.error == null).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: RefreshIndicator(
        onRefresh: _syncNow,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: Services.api.online,
              builder: (context, online, _) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: (online ? AixoloColors.success : AixoloColors.warning).withValues(alpha: 0.12),
                    child: Icon(online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                        color: online ? AixoloColors.success : AixoloColors.warning),
                  ),
                  title: Text(online ? 'Connected' : 'Offline', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: ValueListenableBuilder<int>(
                    valueListenable: Services.tracker.pending,
                    builder: (context, pings, _) => Text(
                        '${waiting.length} action${waiting.length == 1 ? '' : 's'} and $pings location${pings == 1 ? '' : 's'} waiting'),
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: _syncing ? null : _syncNow,
                    child: _syncing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Sync now'),
                  ),
                ),
              ),
            ),
            Card(
              child: ValueListenableBuilder<DateTime?>(
                valueListenable: WarmUp.lastDone,
                builder: (context, last, _) => ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8EFFF),
                    child: Icon(Icons.download_for_offline_rounded, color: AixoloColors.primary),
                  ),
                  title: const Text('Ready for offline', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(last == null
                      ? "Customers, products and today's route are saved while you are online"
                      : 'Saved at ${_when(last)} · customers, products, route, forms'),
                  trailing: TextButton(
                    onPressed: _syncing
                        ? null
                        : () async {
                            setState(() => _syncing = true);
                            await WarmUp.run(force: true);
                            if (mounted) {
                              setState(() => _syncing = false);
                              showSnack(context,
                                  Services.api.online.value ? 'Saved for offline use' : 'You are offline - try again with network');
                            }
                          },
                    child: const Text('Refresh'),
                  ),
                ),
              ),
            ),
            if (failed.isNotEmpty) ...[
              const _Heading('Could not be saved'),
              for (final item in failed)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AixoloColors.danger, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(item.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Text(_when(item.createdAt), style: const TextStyle(color: AixoloColors.muted, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(item.error!, style: const TextStyle(color: AixoloColors.danger)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(onPressed: () => _discard(item), child: const Text('Discard')),
                            const SizedBox(width: 6),
                            FilledButton.tonal(
                              onPressed: () async {
                                await Services.outbox.retry(item.uuid);
                                await _reload();
                              },
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            if (waiting.isNotEmpty) ...[
              const _Heading('Waiting to sync · oldest first'),
              Card(
                child: Column(
                  children: [
                    for (final item in waiting)
                      ListTile(
                        leading: const Icon(Icons.schedule_rounded, color: AixoloColors.warning),
                        title: Text(item.label),
                        subtitle: Text('Done at ${_when(item.createdAt)}'),
                      ),
                  ],
                ),
              ),
            ],
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Column(
                  children: [
                    Icon(Icons.cloud_done_rounded, size: 56, color: AixoloColors.success),
                    SizedBox(height: 10),
                    Text('Everything has reached the office.', style: TextStyle(color: AixoloColors.muted)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: AixoloColors.muted)),
      );
}
