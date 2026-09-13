import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Money this employee has collected, and what is still to be handed over.
class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _deposits = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final month = await Services.api.get('/api/v1/collections') as Map<String, dynamic>;
      final deposits = (await Services.api.get('/api/v1/deposits') as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _data = month;
        _deposits = deposits;
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

  Future<void> _submitDeposit(Map<String, dynamic> pending) async {
    final reference = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hand over to the office'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${fmtMoney(pending['amount'] as num?, _data?['currency'] as String?)} '
                'from ${pending['count']} collections will be marked as submitted.'),
            const SizedBox(height: 12),
            TextField(
              controller: reference,
              decoration: const InputDecoration(labelText: 'Slip / receipt number (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Submit')),
        ],
      ),
    );
    reference.dispose();
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await Services.outbox.submit('/api/v1/deposits', {'reference': reference.text.trim(), 'uuid': const Uuid().v4()});
      Services.refresh.value++;
      if (mounted) showSnack(context, 'Submitted to the office');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Collections')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && data == null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (data != null) ...[
                        _pendingCard(data['pending'] as Map<String, dynamic>? ?? const {}),
                        const SizedBox(height: 12),
                        SectionCard(
                          title: 'Collected this month',
                          action: Text(fmtMoney(data['total_amount'] as num?, data['currency'] as String?),
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          child: Column(
                            children: [
                              for (final c in (data['collections'] as List).cast<Map<String, dynamic>>())
                                _collectionTile(c),
                              if ((data['collections'] as List).isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text('Nothing collected yet this month.',
                                      style: TextStyle(color: AixoloColors.muted)),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SectionCard(
                        title: 'My deposits',
                        child: Column(
                          children: [
                            for (final d in _deposits)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('${d['name']}'),
                                subtitle: Text('${d['count']} collections · ${fmtTime(d['submitted_at'])}'),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(fmtMoney(d['amount'] as num?, d['currency'] as String?),
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                    StatusBadge('${d['state']}'),
                                  ],
                                ),
                              ),
                            if (_deposits.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('No deposits yet.', style: TextStyle(color: AixoloColors.muted)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _pendingCard(Map<String, dynamic> pending) {
    final amount = pending['amount'] as num? ?? 0;
    final blocked = pending['blocked'] == true;
    final count = pending['count'] as int? ?? 0;
    if (count == 0) {
      return SectionCard(
        title: 'Nothing to hand over',
        child: const Text('All the money you collected has reached the office.',
            style: TextStyle(color: AixoloColors.muted)),
      );
    }
    final reason = blocked
        ? (pending['over_amount'] == true
            ? 'You are holding more than the allowed limit. Please submit your cash to the office — check-in is blocked until then.'
            : 'You have held this money for too many days. Please submit your cash to the office — check-in is blocked until then.')
        : 'Hand this over to the office to keep your check-ins working.';
    return Card(
      color: (blocked ? AixoloColors.danger : AixoloColors.warning).withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(blocked ? Icons.block_rounded : Icons.account_balance_wallet_rounded,
                    color: blocked ? AixoloColors.danger : AixoloColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('With you: ${fmtMoney(amount, _data?['currency'] as String?)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                Text('$count items', style: const TextStyle(color: AixoloColors.muted)),
              ],
            ),
            const SizedBox(height: 8),
            Text(reason),
            const SizedBox(height: 12),
            GradientButton(
              label: 'Submit to Office',
              icon: Icons.upload_rounded,
              busy: _busy,
              onPressed: _busy ? null : () => _submitDeposit(pending),
            ),
          ],
        ),
      ),
    );
  }

  Widget _collectionTile(Map<String, dynamic> c) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${c['contact']?['name'] ?? '-'}'),
      subtitle: Text([
        '${c['mode']?['name'] ?? ''}',
        if (asText(c['reference']) != null) '${c['reference']}',
        fmtTime(c['date']),
      ].join(' · ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(fmtMoney(c['amount'] as num?, c['currency'] as String?),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          StatusBadge('${c['state']}'),
        ],
      ),
    );
  }
}
