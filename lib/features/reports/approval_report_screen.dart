import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/busy.dart';
import '../../widgets/common.dart';

/// Approval Report (Manager Mode, Reports): what the manager received, approved and rejected for a
/// period, each request with its type, employee, details and date. Rejected ones show the reason.
///
/// The server answers `GET /api/v1/approvals/report?start&end` with
/// `{counts: {received, approved, rejected, pending}, items: [{id, kind, kind_label, title, employee: {id, name},
/// detail, date, state: approved|rejected|pending, reason}]}` and prepares the file at
/// `POST /api/v1/approvals/report/export {start, end, format: excel|pdf, state, kind, employee_id}` → `{path}`.
class ApprovalReportScreen extends StatefulWidget {
  const ApprovalReportScreen({super.key});

  @override
  State<ApprovalReportScreen> createState() => _ApprovalReportScreenState();
}

class _ApprovalReportScreenState extends State<ApprovalReportScreen> {
  static const _green = Color(0xFF16A34A);
  static const _red = Color(0xFFDC2626);
  static const _amber = Color(0xFFF59E0B);

  /// The approval kinds the app knows, as the Approvals screen names them.
  static const _kindLabels = {
    'beats': 'New Beat',
    'beat': 'New Beat',
    'contacts': 'New Outlet',
    'clients': 'New Outlet',
    'notes': 'Debit / Credit Note',
    'returns': 'Return',
    'leaves': 'Leave',
    'leave': 'Leave',
    'regularisation': 'Attendance Fix',
    'expenses': 'Expense',
    'allowances': 'TA',
    'da': 'DA',
    'handovers': 'Payment Handover',
    'deposits': 'Payment in Hand',
    'access': 'Contact Access',
  };

  String _preset = 'month';
  late DateTime _start;
  late DateTime _end;
  String? _state; // approved | rejected | pending; null = everything received
  String? _kind;
  int? _employee;

  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _notOnServer = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setPreset('month', load: false);
    _load();
  }

  void _setPreset(String preset, {bool load = true}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _preset = preset;
      _end = today;
      _start = switch (preset) {
        'today' => today,
        'week' => today.subtract(Duration(days: today.weekday - 1)),
        _ => DateTime(today.year, today.month),
      };
    });
    if (load) _load();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (picked == null) return;
    setState(() {
      _preset = 'custom';
      _start = picked.start;
      _end = picked.end;
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Services.api.get('/api/v1/approvals/report', query: {
        'start': fmtDate(_start),
        'end': fmtDate(_end),
        // Working as an employee: only the person's own requests.
        if (!Services.managerMode.value) 'scope': 'me',
      });
      if (mounted) {
        setState(() {
          _data = data is Map ? data.cast<String, dynamic>() : {'items': data};
          _notOnServer = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => e.status == 404 ? (_notOnServer = true, _data = null) : _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _items => ((_data?['items'] as List?) ?? []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

  static String _stateOf(Map<String, dynamic> r) {
    final s = '${r['state'] ?? r['status'] ?? ''}'.toLowerCase();
    if (s.startsWith('approv') || s == 'done' || s == 'validate' || s == 'confirmed') return 'approved';
    if (s.startsWith('reject') || s == 'refuse' || s == 'refused' || s == 'cancel') return 'rejected';
    return 'pending';
  }

  static String? _name(dynamic v) => v is Map ? asText(v['name']) : asText(v);

  String _kindLabel(Map<String, dynamic> r) => asText(r['kind_label']) ?? _kindLabels['${r['kind']}'] ?? asText(r['kind']) ?? 'Request';

  int _count(String key) {
    final sent = (_data?['counts'] as Map?)?[key];
    if (sent is num) return sent.toInt();
    final items = _items;
    return key == 'received' ? items.length : items.where((r) => _stateOf(r) == key).length;
  }

  String get _range {
    String day(DateTime d) => '${d.day} ${monthNames[d.month - 1].substring(0, 3)}';
    return _start == _end ? '${day(_start)} ${_start.year}' : '${day(_start)} – ${day(_end)} ${_end.year}';
  }

  String _shortDate(dynamic v) {
    final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
    return d == null ? '' : '${d.day} ${monthNames[d.month - 1].substring(0, 3)}';
  }

  List<Map<String, dynamic>> get _shown => _items.where((r) {
        if (_state != null && _stateOf(r) != _state) return false;
        if (_kind != null && _kindLabel(r) != _kind) return false;
        if (_employee != null && (r['employee'] is! Map || (r['employee'] as Map)['id'] != _employee)) return false;
        return true;
      }).toList();

  Widget _countBox(String key, String label, Color colour) {
    final on = _state == key || (key == 'received' && _state == null);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: key == 'received' ? Colors.white : colour.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _state = key == 'received' ? null : (_state == key ? null : key)),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: on ? colour : colour.withValues(alpha: 0.35), width: on ? 1.6 : 1),
              ),
              child: Column(children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
                  child: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                Text('${_count(key)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                FittedBox(child: Text('$label ›', style: const TextStyle(fontSize: 11, color: AppColors.muted))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _presetChip(String key, String label) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(_preset == key ? '✓ $label' : label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          selected: _preset == key,
          showCheckmark: false,
          onSelected: (_) => _setPreset(key),
        ),
      );

  Widget _filters() {
    final kinds = {for (final r in _items) _kindLabel(r)}.toList()..sort();
    final people = <int, String>{
      for (final r in _items)
        if (r['employee'] is Map && (r['employee'] as Map)['id'] is int) (r['employee'] as Map)['id'] as int: '${(r['employee'] as Map)['name']}',
    };
    Widget menu<T>(String label, T? value, Map<T, String> options, void Function(T?) pick) => PopupMenuButton<Object>(
          onSelected: (v) => setState(() => pick(v == '' ? null : v as T)),
          itemBuilder: (_) => [
            const PopupMenuItem(value: '', child: Text('All')),
            for (final e in options.entries) PopupMenuItem(value: e.key as Object, child: Text(e.value)),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: value == null ? AppColors.border : AppColors.primary),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(value == null ? label : options[value] ?? label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
            ]),
          ),
        );
    return Row(children: [
      Flexible(child: menu<String>('All types', _kind, {for (final k in kinds) k: k}, (v) => _kind = v)),
      // Only the manager's team view has other employees to choose from.
      if (Services.managerMode.value) ...[
        const SizedBox(width: 8),
        Flexible(child: menu<int>('All employees', _employee, people, (v) => _employee = v)),
      ],
    ]);
  }

  Widget _row(Map<String, dynamic> r) {
    final state = _stateOf(r);
    final colour = switch (state) { 'approved' => _green, 'rejected' => _red, _ => _amber };
    final title = [_kindLabel(r), if (asText(r['title']) != null) asText(r['title'])].join(' · ');
    final reason = asText(r['reason']);
    final line = [
      if (_name(r['employee']) != null) _name(r['employee'])!,
      if (state == 'rejected' && reason != null) 'Reason: $reason' else if (asText(r['detail']) != null) asText(r['detail'])!,
      if (_shortDate(r['date']).isNotEmpty) _shortDate(r['date']),
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(r),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: colour),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(20)),
                    child: Text('${state[0].toUpperCase()}${state.substring(1)}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// One request in full: everything the server sent about it.
  void _open(Map<String, dynamic> r) {
    final state = _stateOf(r);
    final facts = <(String, String)>[
      ('Type', _kindLabel(r)),
      if (asText(r['title']) != null) ('Request', asText(r['title'])!),
      if (_name(r['employee']) != null) ('Employee', _name(r['employee'])!),
      if (asText(r['detail']) != null) ('Details', asText(r['detail'])!),
      if (_shortDate(r['date']).isNotEmpty) ('Date', _shortDate(r['date'])),
      ('Status', '${state[0].toUpperCase()}${state.substring(1)}'),
      if (_name(r['decided_by']) != null) ('Decided by', _name(r['decided_by'])!),
      if (_shortDate(r['decided_at']).isNotEmpty) ('Decided on', _shortDate(r['decided_at'])),
      if (asText(r['reason']) != null) ('Reason', asText(r['reason'])!),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_kindLabel(r), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 10),
            for (final (label, value) in facts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 96, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
                  Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _download() async {
    final format = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.grid_on_rounded, color: AppColors.success),
            title: const Text('Excel', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Approval Report · $_range'),
            onTap: () => Navigator.pop(sheet, 'excel'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.danger),
            title: const Text('PDF', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('The same report as a PDF'),
            onTap: () => Navigator.pop(sheet, 'pdf'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (format == null || !mounted) return;
    try {
      final file = await withBusy(context, 'Preparing the report…', () async {
        final r = await Services.api.post('/api/v1/approvals/report/export', {
          'start': fmtDate(_start),
          'end': fmtDate(_end),
          'format': format,
          if (_state != null) 'state': _state,
          if (_kind != null) 'kind': _kind,
          if (_employee != null) 'employee_id': _employee,
          if (!Services.managerMode.value) 'scope': 'me',
        }) as Map<String, dynamic>;
        final response = await http.get(Uri.parse(await Services.api.url('${r['path']}')), headers: await Services.api.authHeaders());
        if (response.statusCode != 200) throw Exception('The report could not be downloaded (${response.statusCode}).');
        final dir = await getTemporaryDirectory();
        final out = File('${dir.path}/Approval_Report_${fmtDate(_start)}_${fmtDate(_end)}.${format == 'excel' ? 'xlsx' : 'pdf'}');
        await out.writeAsBytes(response.bodyBytes);
        return out;
      });
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile(file.path,
              mimeType: format == 'pdf' ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
        ],
        subject: 'Approval Report $_range',
      ));
    } on ApiException catch (e) {
      if (mounted) showProblem(context, e.status == 404 ? 'Downloading the Approval Report is not switched on yet. Please ask the office.' : e.message);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _shown;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Approval Report', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
          Text(_range, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton.outlined(
                  tooltip: 'Choose dates',
                  isSelected: _preset == 'custom',
                  onPressed: _pickRange,
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                ),
              ),
              _presetChip('today', 'Today'),
              _presetChip('week', 'This week'),
              _presetChip('month', 'This month'),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            _countBox('received', 'Received', AppColors.muted),
            _countBox('approved', 'Approved', _green),
            _countBox('rejected', 'Rejected', _red),
            _countBox('pending', 'Pending', _amber),
          ]),
          if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
          if (_error != null) ErrorView(message: _error!, onRetry: _load),
          if (_notOnServer)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: const Text('The Approval Report is not switched on yet on the server. Please ask the office.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF9A3412))),
            ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 12),
            _filters(),
          ],
          const SizedBox(height: 12),
          if (!_loading && !_notOnServer && _error == null && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No requests for these dates.', style: TextStyle(color: AppColors.muted))),
            ),
          for (final r in rows) _row(r),
          const SizedBox(height: 8),
          GradientButton(label: 'Download (Excel / PDF)', icon: Icons.download_rounded, onPressed: _notOnServer ? null : _download),
        ]),
      ),
    );
  }
}
