import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/skeleton.dart';

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
            ? const LoadingView()
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
                        subtitle: Text(
                            (item['which'] == 'in'
                                    ? 'Punch-in corrected to ${fmtTime(item['check_in'])}'
                                    : item['which'] == 'out'
                                        ? 'Punch-out corrected to ${fmtTime(item['check_out'])}'
                                        : 'In ${fmtTime(item['check_in'])} · Out ${fmtTime(item['check_out'])}') +
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

/// One punch is corrected at a time: the other stays as it was recorded. The reason is compulsory and goes to
/// the manager with the request.
class _RegularisationFormState extends State<_RegularisationForm> {
  DateTime _date = DateTime.now();
  Map<String, dynamic>? _recorded;
  bool _loadingDay = true;
  String _which = 'out';
  TimeOfDay? _time;
  final _reasonText = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadDay();
  }

  @override
  void dispose() {
    _reasonText.dispose();
    super.dispose();
  }

  DateTime _at(TimeOfDay t) => DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);

  Future<void> _loadDay() async {
    setState(() => _loadingDay = true);
    try {
      final data = await Services.api.get('/api/v1/attendance/day', query: {'date': fmtDate(_date)}) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _recorded = data;
        // The punch that is missing is the one most likely to be wrong.
        _which = data['check_out'] == null && data['check_in'] != null ? 'out' : _which;
      });
    } catch (_) {
      if (mounted) setState(() => _recorded = null);
    } finally {
      if (mounted) setState(() => _loadingDay = false);
    }
  }

  String _recordedText(String key) {
    final v = _recorded?[key];
    return v == null ? '– (missed)' : fmtTime(v);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _loadDay();
    }
  }

  Future<void> _submit() async {
    if (_time == null) {
      showSnack(context, 'Enter the correct punch-${_which == 'in' ? 'in' : 'out'} time.');
      return;
    }
    if (_reasonText.text.trim().isEmpty) {
      showSnack(context, 'Give the reason for the correction.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Services.outbox.submit('/api/v1/attendance/regularisations', {
        'uuid': const Uuid().v4(),
        'date': fmtDate(_date),
        'which': _which,
        'time': _at(_time!).toUtc().toIso8601String(),
        'reason': 'other',
        'note': _reasonText.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _half(String code, String text) {
    final on = _which == code;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() {
          _which = code;
          _time = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(on ? '✓ $text' : text,
              style: TextStyle(fontWeight: FontWeight.w800, color: on ? AppColors.primary : AppColors.text)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = _which == 'in' ? 'punch-in' : 'punch-out';
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Attendance Correction', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          Text(fmtDate(_date), style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
        ]),
        actions: [IconButton(tooltip: 'Change the day', icon: const Icon(Icons.event_rounded), onPressed: _pickDate)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: _loadingDay
                ? const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Recorded', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Expanded(child: Text('Punch in', style: TextStyle(color: AppColors.muted))),
                      Text(_recordedText('check_in'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Expanded(child: Text('Punch out', style: TextStyle(color: AppColors.muted))),
                      Text(_recordedText('check_out'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ]),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [_half('in', 'Punch in'), _half('out', 'Punch out')]),
          ),
          const SizedBox(height: 16),
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Correct $label time', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            const TextSpan(text: ' *', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w900)),
          ])),
          const SizedBox(height: 6),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final picked = await showTimePicker(
                  context: context, initialTime: _time ?? const TimeOfDay(hour: 9, minute: 30));
              if (picked != null) setState(() => _time = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(_time == null ? 'Tap to set the time' : _time!.format(context),
                      style: TextStyle(color: _time == null ? AppColors.muted : AppColors.text)),
                ),
                const Icon(Icons.schedule_rounded, size: 18, color: AppColors.muted),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          const Text.rich(TextSpan(children: [
            TextSpan(text: 'Reason', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            TextSpan(text: ' *', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w900)),
          ])),
          const SizedBox(height: 6),
          TextField(
            controller: _reasonText,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Why is the punch wrong?',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
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
