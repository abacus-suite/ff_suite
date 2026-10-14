import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

/// A new Travel Allowance: choose the day, see the meter, the tracked distance and the split between the
/// assigned route and other routes priced per km, then send it to the manager.
class TravelFormScreen extends StatefulWidget {
  const TravelFormScreen({super.key});

  @override
  State<TravelFormScreen> createState() => _TravelFormScreenState();
}

class _TravelFormScreenState extends State<TravelFormScreen> {
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
    });
    try {
      final d = await Services.api.get('/api/v1/travel/day', query: {'date': fmtDate(_day)}) as Map<String, dynamic>;
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
      helpText: 'Date of travel',
    );
    if (picked != null) {
      setState(() => _day = DateUtils.dateOnly(picked));
      _load();
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await Services.api.post('/api/v1/travel/submit', {'date': fmtDate(_day)});
      if (!mounted) return;
      showSnack(context, 'Sent to your manager for approval');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final currency = d?['currency'] as String?;
    final odo = (d?['odometer'] as Map?)?.cast<String, dynamic>() ?? const {};
    final own = (d?['own'] as Map?)?.cast<String, dynamic>() ?? const {};
    final other = (d?['other'] as Map?)?.cast<String, dynamic>() ?? const {};
    final na = odo['na'] == true;
    final state = '${d?['state'] ?? ''}';
    final locked = state == 'submitted' || state == 'approved';

    Widget line(String label, String value, {bool bold = false, Color? colour}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
            Text(value,
                style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w700, color: colour, fontSize: bold ? 16 : 14)),
          ]),
        );

    Widget card(String title, IconData icon, List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            ]),
            const SizedBox(height: 6),
            ...children,
          ]),
        );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('New Travel Allowance')),
      bottomNavigationBar: d == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: GradientButton(
                  label: locked
                      ? (state == 'approved' ? 'Approved' : 'With your manager')
                      : 'Submit for approval',
                  icon: Icons.send_rounded,
                  busy: _busy,
                  onPressed: (d['can_submit'] == true && !_busy) ? _submit : null,
                ),
              ),
            ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        InkWell(
          onTap: _pick,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              const Icon(Icons.calendar_month_rounded, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Date', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  Text('${_day.day} ${monthNames[_day.month - 1]} ${_day.year}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ]),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        if (_loading) const Padding(padding: EdgeInsets.all(40), child: LoadingView()),
        if (_error != null) ErrorView(message: _error!, onRetry: _load),
        if (d != null) ...[
          card('Distance', Icons.speed_rounded, [
            line('Opening reading', odo['opening'] == null ? 'NA' : '${odo['opening']}'),
            line('Closing reading', na || odo['closing'] == null ? 'NA' : '${odo['closing']}'),
            line('From odometer', na ? 'NA' : '${fmtQty(_n(odo['km']))} km', bold: true),
            const Divider(height: 14),
            line('Actual (GPS tracked)', '${fmtQty(_n(d['geo_km']))} km', bold: true),
            if (na)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                    'The odometer is NA for this day (closed automatically or no closing reading), '
                    'so the tracked distance is used.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ),
          ]),
          card('Where you travelled', Icons.alt_route_rounded, [
            line('Own beat', '${fmtQty(_n(own['km']))} km'),
            line('Other beat', '${fmtQty(_n(other['km']))} km'),
            for (final b in ((d['beats'] as List?) ?? []).cast<Map<String, dynamic>>())
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  Icon(b['own'] == true ? Icons.check_circle_rounded : Icons.swap_horiz_rounded,
                      size: 15, color: b['own'] == true ? AppColors.success : AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${b['beat']}', style: const TextStyle(fontSize: 12.5))),
                  Text('${((_n(b['share'])) * 100).round()}%',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                ]),
              ),
          ]),
          card('Amount', Icons.payments_rounded, [
            line('Own beat', '${fmtQty(_n(own['km']))} km × ${fmtMoney(own['rate'] as num?, currency)} = '
                '${fmtMoney(own['amount'] as num?, currency)}'),
            line('Other beat', '${fmtQty(_n(other['km']))} km × ${fmtMoney(other['rate'] as num?, currency)} = '
                '${fmtMoney(other['amount'] as num?, currency)}'),
            const Divider(height: 14),
            line('Total', fmtMoney(d['amount'] as num?, currency), bold: true, colour: AppColors.primary),
            if (_n(own['rate']) == 0 && _n(other['rate']) == 0)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('No per-km rate is set for you yet. Ask the office to set it.',
                    style: TextStyle(fontSize: 12, color: AppColors.warning)),
              ),
          ]),
        ],
      ]),
    );
  }
}
