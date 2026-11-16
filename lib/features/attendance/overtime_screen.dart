import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

String _mins(num? minutes) {
  final m = (minutes ?? 0).round();
  if (m <= 0) return '0 min';
  final h = m ~/ 60;
  final r = m % 60;
  return [if (h > 0) '$h h', if (r > 0 || h == 0) '$r min'].join(' ');
}

String _day(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return iso ?? '';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[d.weekday - 1]}, ${d.day} ${monthNames[d.month - 1].substring(0, 3)}';
}

(Color, String) _look(String state) => switch (state) {
      'submitted' => (AppColors.sky, 'Waiting for approval'),
      'approved' => (AppColors.success, 'Approved'),
      'rejected' => (AppColors.danger, 'Not approved'),
      _ => (AppColors.muted, 'Not sent'),
    };

/// The hours worked beyond the shift, day by day: send them for approval; once approved they are added to the
/// Compensatory Off leave in hours.
class OvertimeScreen extends StatefulWidget {
  const OvertimeScreen({super.key});

  @override
  State<OvertimeScreen> createState() => _OvertimeScreenState();
}

class _OvertimeScreenState extends State<OvertimeScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _sending = false;
  final Set<int> _picked = {};

  String get _key => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Services.api.get('/api/v1/overtime', query: {'month': _key}) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
          _picked
            ..clear()
            ..addAll(_rows.where((r) => r['state'] == 'draft').map((r) => r['id'] as int));
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _rows => ((_data?['rows'] as List?) ?? []).cast<Map<String, dynamic>>();

  void _shift(int by) {
    setState(() {
      _month = DateTime(_month.year, _month.month + by);
      _data = null;
    });
    _load();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await Services.api.post('/api/v1/overtime/send', {'ids': _picked.toList()});
      if (mounted) showSnack(context, 'Sent for approval');
      await _load();
    } catch (e) {
      if (mounted) await showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _figure(String label, num? minutes, Color tint) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_mins(minutes), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: tint)),
            Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    final data = _data;
    final isManager = (Services.auth.profile?.isManager ?? false) && Services.managerMode.value;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Overtime', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
        actions: [
          if (isManager)
            TextButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OvertimeApprovalScreen()));
              },
              icon: const Icon(Icons.fact_check_rounded),
              label: const Text('To approve'),
            ),
        ],
      ),
      bottomNavigationBar: _picked.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GradientButton(
                    label: 'Send for approval (${_picked.length})', icon: Icons.send_rounded, busy: _sending, onPressed: _send),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
          Card(
            child: Row(children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
              Expanded(
                  child: Center(
                      child: Text('${monthNames[_month.month - 1]} ${_month.year}',
                          style: const TextStyle(fontWeight: FontWeight.w700)))),
              IconButton(onPressed: isCurrent ? null : () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
            ]),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) ErrorView(message: _error!, onRetry: _load),
          if (data != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              _figure('Not sent', data['to_send_minutes'] as num?, AppColors.muted),
              const SizedBox(width: 8),
              _figure('Waiting', data['waiting_minutes'] as num?, AppColors.sky),
              const SizedBox(width: 8),
              _figure('Approved', data['approved_minutes'] as num?, AppColors.success),
            ]),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.fromLTRB(2, 4, 2, 8),
              child: Text(
                  'Time worked beyond your shift. Once your manager approves it, it is added to your Compensatory Off, in hours.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          ],
          if (data != null && _rows.isEmpty && !_loading)
            const EmptyView(icon: Icons.more_time_rounded, text: 'No overtime this month'),
          for (final r in _rows)
            Builder(builder: (context) {
              final (tint, label) = _look('${r['state']}');
              final draft = r['state'] == 'draft';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(6, 10, 14, 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: Row(children: [
                  if (draft)
                    Checkbox(
                      value: _picked.contains(r['id']),
                      onChanged: (v) => setState(() => v == true ? _picked.add(r['id'] as int) : _picked.remove(r['id'])),
                    )
                  else
                    const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_day(r['date'] as String?), style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('Worked ${_mins(r['worked_minutes'] as num?)} · shift ${_mins(r['expected_minutes'] as num?)}',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      if (r['state'] == 'approved')
                        Text('Approved ${_mins(r['approved_minutes'] as num?)} of ${_mins(r['overtime_minutes'] as num?)}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
                      // What the manager changed, and why.
                      if (r['state'] == 'approved' && (r['approved_minutes'] as num) < (r['overtime_minutes'] as num) && asText(r['note']) != null)
                        Text('Adjusted by your manager: ${r['note']}',
                            style: const TextStyle(fontSize: 12, color: AppColors.warning, fontWeight: FontWeight.w600)),
                      if (r['state'] == 'rejected' && asText(r['note']) != null)
                        Text('Reason: ${r['note']}',
                            style: const TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_mins(r['overtime_minutes'] as num?), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text(label, style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: 10.5)),
                    ),
                  ]),
                ]),
              );
            }),
        ]),
      ),
    );
  }
}

/// The manager decides on one overtime: the time can be changed (1 hour sent can be approved as 30 minutes, or as none),
/// and a change or a rejection needs a reason. True when it was decided.
Future<bool> decideOvertime(BuildContext context, Map<String, dynamic> r) async {
  final sent = (r['overtime_minutes'] as num).toInt();
  var minutes = sent;
  final why = TextEditingController();
  final typed = TextEditingController(text: '$sent');
  final result = await showModalBottomSheet<(int, String)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(
      builder: (context, setSheet) {
        final changed = minutes < sent;
        final needReason = changed;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${(r['employee'] as Map?)?['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                Text('${_day(r['date'] as String?)} · worked ${_mins(r['worked_minutes'] as num?)}, shift ${_mins(r['expected_minutes'] as num?)}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                const SizedBox(height: 14),
                Text('Sent: ${_mins(sent)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('Approve', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                // Tap the number and type the minutes to approve: less than what was sent, never more.
                TextField(
                  controller: typed,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: changed ? AppColors.warning : AppColors.primary),
                  onChanged: (v) => setSheet(() => minutes = int.tryParse(v) ?? 0),
                  decoration: InputDecoration(
                    suffixText: 'min',
                    helperText: _mins(minutes <= sent ? minutes : sent),
                    helperStyle: const TextStyle(fontSize: 12.5),
                    errorText: minutes > sent ? 'More than the ${_mins(sent)} sent: enter $sent or less' : null,
                  ),
                ),
                if (changed) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: why,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (_) => setSheet(() {}),
                    decoration: const InputDecoration(
                        labelText: 'Reason for changing it *', hintText: 'The employee will see this'),
                  ),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: AppColors.danger),
                      onPressed: () {
                        if (why.text.trim().isEmpty) {
                          // A rejection needs a reason: show the field first.
                          setSheet(() {
                            minutes = 0;
                            typed.text = '0';
                          });
                        } else {
                          Navigator.pop(sheet, (0, why.text.trim()));
                        }
                      },
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: minutes <= 0 || minutes > sent || (needReason && why.text.trim().isEmpty)
                          ? null
                          : () => Navigator.pop(sheet, (minutes, why.text.trim())),
                      child: Text('Approve ${_mins(minutes)}'),
                    ),
                  ),
                ]),
                if (needReason && why.text.trim().isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Say why the time is changed, then approve (or reject).',
                        style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ),
              ]),
            ),
          ),
        );
      },
    ),
  );
  why.dispose();
  typed.dispose();
  if (result == null || !context.mounted) return false;
  try {
    await Services.api.post('/api/v1/overtime/${r['id']}/decide',
        {'minutes': result.$1, 'reject': result.$1 == 0, 'reason': result.$2});
    if (context.mounted) showSnack(context, result.$1 == 0 ? 'Not approved' : 'Approved ${_mins(result.$1)}');
    return true;
  } catch (e) {
    if (context.mounted) await showProblem(context, e.toString());
    return false;
  }
}

/// The manager: the overtime sent by the team (also in Approvals, as a category).
class OvertimeApprovalScreen extends StatefulWidget {
  const OvertimeApprovalScreen({super.key});

  @override
  State<OvertimeApprovalScreen> createState() => _OvertimeApprovalScreenState();
}

class _OvertimeApprovalScreenState extends State<OvertimeApprovalScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Services.api.get('/api/v1/overtime/to-approve') as Map<String, dynamic>;
      if (mounted) setState(() => (_rows = ((data['rows'] as List?) ?? []).cast<Map<String, dynamic>>(), _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Overtime to approve', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20))),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : rows == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    if (rows.isEmpty) const EmptyView(icon: Icons.more_time_rounded, text: 'Nothing waiting for you'),
                    for (final r in rows) overtimeCard(context, r, () async {
                      if (await decideOvertime(context, r)) _load();
                    }),
                  ]),
                ),
    );
  }
}

/// One overtime waiting for the manager: who, the day, the time sent; tap to decide.
Widget overtimeCard(BuildContext context, Map<String, dynamic> r, VoidCallback onTap) => Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        title: Text('${(r['employee'] as Map?)?['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${_day(r['date'] as String?)} · worked ${_mins(r['worked_minutes'] as num?)} · shift ${_mins(r['expected_minutes'] as num?)}'),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_mins(r['overtime_minutes'] as num?), style: const TextStyle(fontWeight: FontWeight.w900)),
          const Text('Tap to decide', style: TextStyle(fontSize: 10.5, color: AppColors.primary)),
        ]),
      ),
    );
