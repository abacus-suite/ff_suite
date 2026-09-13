import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// For managers and the office: money handed over by the team, waiting to be received.
class DepositsReceiveScreen extends StatefulWidget {
  const DepositsReceiveScreen({super.key});

  @override
  State<DepositsReceiveScreen> createState() => _DepositsReceiveScreenState();
}

class _DepositsReceiveScreenState extends State<DepositsReceiveScreen> {
  List<Map<String, dynamic>> _deposits = [];
  bool _loading = true;
  int? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = (await Services.api.get('/api/v1/deposits/to-receive') as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _deposits = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _decide(Map<String, dynamic> deposit, bool received) async {
    setState(() => _busyId = deposit['id'] as int);
    try {
      await Services.outbox.submit('/api/v1/deposits/${deposit['id']}/${received ? 'receive' : 'reject'}', {'uuid': const Uuid().v4()});
      Services.refresh.value++;
      if (mounted) showSnack(context, received ? 'Marked as received' : 'Sent back to the employee');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Money To Receive')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _deposits.isEmpty
              ? ErrorView(message: _error!, onRetry: _load)
              : _deposits.isEmpty
                  ? const EmptyView(
                      icon: Icons.verified_rounded,
                      text: 'Nothing waiting. Every deposit from your team has been received.')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final d in _deposits) _depositCard(d),
                        ],
                      ),
                    ),
    );
  }

  Widget _depositCard(Map<String, dynamic> d) {
    final busy = _busyId == d['id'];
    final lines = (d['collections'] as List? ?? const []).cast<Map<String, dynamic>>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        title: '${d['employee']?['name'] ?? '-'} · ${d['name']}',
        action: Text(fmtMoney(d['amount'] as num?, d['currency'] as String?),
            style: const TextStyle(fontWeight: FontWeight.w800)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Submitted ${fmtTime(d['submitted_at'])}'
                '${asText(d['reference']) != null ? ' · slip ${d['reference']}' : ''}',
                style: const TextStyle(color: AixoloColors.muted)),
            const SizedBox(height: 8),
            for (final c in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text('${c['contact']?['name'] ?? '-'} · ${c['mode']?['name'] ?? ''}')),
                    Text(fmtMoney(c['amount'] as num?, c['currency'] as String?)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GradientButton(
                    label: 'Received',
                    icon: Icons.check_rounded,
                    busy: busy,
                    onPressed: busy ? null : () => _decide(d, true),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: busy ? null : () => _decide(d, false),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
