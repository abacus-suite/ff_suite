import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/services.dart';

const reasons = <String, String>{
  'battery': 'Phone battery died',
  'network': 'No network',
  'forgot': 'Forgot to punch',
  'field_duty': 'Field duty / outstation',
  'other': 'Other',
};

const _stateColors = <String, Color>{
  'submitted': Colors.blue,
  'approved': Colors.green,
  'rejected': Colors.red,
  'draft': Colors.grey,
};

class RegularisationScreen extends StatefulWidget {
  const RegularisationScreen({super.key});

  @override
  State<RegularisationScreen> createState() => _RegularisationScreenState();
}

class _RegularisationScreenState extends State<RegularisationScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await Services.api.get('/api/v1/attendance/regularisations') as List;
      setState(() {
        _items = list.cast<Map<String, dynamic>>();
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const _RegularisationForm()));
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Correction')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New request'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                children: [
                  if (_error != null) Text(_error!),
                  if (_items.isEmpty && _error == null)
                    const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No requests yet'))),
                  for (final item in _items)
                    Card(
                      child: ListTile(
                        title: Text('${item['date']} · ${reasons[item['reason']] ?? item['reason']}'),
                        subtitle: Text('In ${fmtTime(item['check_in'])} · Out ${fmtTime(item['check_out'])}'
                            '${item['note'] != null ? '\n${item['note']}' : ''}'),
                        trailing: Chip(
                          label: Text('${item['state']}'.toUpperCase(), style: const TextStyle(fontSize: 11)),
                          backgroundColor: (_stateColors[item['state']] ?? Colors.grey).withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _RegularisationForm extends StatefulWidget {
  const _RegularisationForm();

  @override
  State<_RegularisationForm> createState() => _RegularisationFormState();
}

class _RegularisationFormState extends State<_RegularisationForm> {
  DateTime _date = DateTime.now();
  TimeOfDay _in = const TimeOfDay(hour: 9, minute: 30);
  TimeOfDay _out = const TimeOfDay(hour: 18, minute: 30);
  String _reason = 'forgot';
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  DateTime _at(TimeOfDay t) => DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);

  Future<void> _submit() async {
    if (!_at(_out).isAfter(_at(_in))) {
      showSnack(context, 'Punch-out must be after punch-in.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Services.outbox.submit('/api/v1/attendance/regularisations', {
        'uuid': const Uuid().v4(),
        'date': fmtDate(_date),
        'check_in': _at(_in).toUtc().toIso8601String(),
        'check_out': _at(_out).toUtc().toIso8601String(),
        'reason': _reason,
        'note': _note.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Correction Request')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Date'),
            trailing: Text(fmtDate(_date)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime.now().subtract(const Duration(days: 60)),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          ListTile(
            leading: const Icon(Icons.login),
            title: const Text('Punch in'),
            trailing: Text(_in.format(context)),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: _in);
              if (picked != null) setState(() => _in = picked);
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Punch out'),
            trailing: Text(_out.format(context)),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: _out);
              if (picked != null) setState(() => _out = picked);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
            items: reasons.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setState(() => _reason = v ?? 'other'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_busy ? 'Sending...' : 'Send to manager'),
            ),
          ),
        ],
      ),
    );
  }
}
