import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Plan a route day: pick the day, pick the route, keep the customers you will reach.
class PlanDayScreen extends StatefulWidget {
  const PlanDayScreen({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  State<PlanDayScreen> createState() => _PlanDayScreenState();
}

class _PlanDayScreenState extends State<PlanDayScreen> {
  late DateTime _date;
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _customers = [];
  final Set<int> _selected = {};
  final Set<int> _visited = {};
  Map<String, dynamic>? _route;
  Map<String, dynamic>? _plannedDay;
  bool _loading = true;
  bool _loadingCustomers = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = widget.initialDate ?? DateTime(now.year, now.month, now.day);
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = (await Services.api.get('/api/v1/route-plan/routes') as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _routes = list;
        _loading = false;
      });
      if (list.length == 1) await _pickRoute(list.first);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickRoute(Map<String, dynamic> route) async {
    setState(() {
      _route = route;
      _loadingCustomers = true;
    });
    await _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final route = _route;
    if (route == null) return;
    setState(() => _loadingCustomers = true);
    try {
      final data = await Services.api
              .get('/api/v1/route-plan/customers?beat_id=${route['id']}&date=${fmtDate(_date)}')
          as Map<String, dynamic>;
      final customers = (data['customers'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _plannedDay = data['day'] as Map<String, dynamic>?;
        _selected
          ..clear()
          ..addAll(customers.where((c) => c['selected'] == true).map((c) => c['id'] as int));
        _visited
          ..clear()
          ..addAll(customers.where((c) => c['visited'] == true).map((c) => c['id'] as int));
        _loadingCustomers = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingCustomers = false);
        showSnack(context, e.toString());
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 120)),
    );
    if (picked == null) return;
    setState(() => _date = picked);
    await _loadCustomers();
  }

  Future<void> _save() async {
    final route = _route;
    if (route == null) {
      showSnack(context, 'Choose a route first.');
      return;
    }
    if (_selected.isEmpty) {
      showSnack(context, 'Keep at least one customer for the day.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Services.outbox.submit('/api/v1/route-plan/days', {
        'uuid': const Uuid().v4(),
        'date': fmtDate(_date),
        'beat_id': route['id'],
        'partner_ids': _selected.toList(),
      });
      Services.refresh.value++;
      if (!mounted) return;
      showSnack(context, '${_selected.length} customers planned for ${fmtDate(_date)}');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _routeDetails(Map<String, dynamic> r) => [
        if (r['route_type'] != null) r['route_type'],
        '${r['customer_count']} customers',
        if ((r['planned_km'] as num? ?? 0) > 0) '${r['planned_km']} km',
      ].join(' · ');

  /// A searchable list: someone with thirty routes finds theirs by typing.
  Future<void> _chooseRoute(String routeLabel) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheet) {
            final q = query.trim().toLowerCase();
            final shown = q.isEmpty
                ? _routes
                : _routes
                    .where((r) => '${r['name']} ${r['route_type'] ?? ''} ${r['city'] ?? ''}'.toLowerCase().contains(q))
                    .toList();
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        autofocus: _routes.length > 8,
                        onChanged: (v) => setSheet(() => query = v),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: 'Search $routeLabel',
                          isDense: true,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('${shown.length} of ${_routes.length}',
                            style: const TextStyle(color: AixoloColors.muted, fontSize: 12)),
                      ),
                    ),
                    Expanded(
                      child: shown.isEmpty
                          ? const Center(child: Text('Nothing matches', style: TextStyle(color: AixoloColors.muted)))
                          : ListView.builder(
                              itemCount: shown.length,
                              itemBuilder: (context, i) {
                                final r = shown[i];
                                final selected = _route?['id'] == r['id'];
                                return ListTile(
                                  leading: Icon(selected ? Icons.check_circle_rounded : Icons.route_rounded,
                                      color: selected ? AixoloColors.success : AixoloColors.primary),
                                  title: Text('${r['name']}',
                                      style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
                                  subtitle: Text(_routeDetails(r)),
                                  onTap: () => Navigator.pop(sheet, r),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (picked != null) _pickRoute(picked);
  }

  @override
  Widget build(BuildContext context) {
    final profile = Services.auth.profile!;
    final routeLabel = profile.routeLabel;
    return Scaffold(
      appBar: AppBar(title: Text('Plan a $routeLabel Day')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _loadRoutes)
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.calendar_month_rounded, color: AixoloColors.primary),
                              title: const Text('Day'),
                              subtitle: Text(_plannedDay == null
                                  ? 'Nothing planned yet on this day'
                                  : 'Already planned: ${_plannedDay!['planned_count']} customers'),
                              trailing: Text(fmtDate(_date),
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              onTap: _pickDate,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(routeLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          if (_routes.isEmpty)
                            EmptyView(
                                icon: Icons.route_rounded,
                                text: 'No $routeLabel is assigned to you yet. Ask the office to assign one.'),
                          if (_routes.isNotEmpty)
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.route_rounded, color: AixoloColors.primary),
                                title: Text(_route == null ? 'Choose a $routeLabel' : '${_route!['name']}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _route == null ? AixoloColors.muted : AixoloColors.text)),
                                subtitle: _route == null
                                    ? Text('${_routes.length} to choose from')
                                    : Text(_routeDetails(_route!)),
                                trailing: const Icon(Icons.search_rounded),
                                onTap: () => _chooseRoute(routeLabel),
                              ),
                            ),
                          const SizedBox(height: 12),
                          if (_loadingCustomers)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_route != null)
                            SectionCard(
                              title: 'Customers (${_selected.length}/${_customers.length})',
                              action: TextButton(
                                onPressed: () => setState(() {
                                  if (_selected.length == _customers.length) {
                                    _selected.clear();
                                    _selected.addAll(_visited);
                                  } else {
                                    _selected
                                      ..clear()
                                      ..addAll(_customers.map((c) => c['id'] as int));
                                  }
                                }),
                                child: Text(_selected.length == _customers.length ? 'Clear all' : 'Select all'),
                              ),
                              child: Column(
                                children: [
                                  for (final c in _customers) _customerTile(c),
                                  if (_customers.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8),
                                      child: Text('This route has no customers yet.',
                                          style: TextStyle(color: AixoloColors.muted)),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: GradientButton(
                          label: 'Save Plan',
                          icon: Icons.event_available_rounded,
                          busy: _busy,
                          onPressed: _busy || _route == null ? null : _save,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _customerTile(Map<String, dynamic> c) {
    final id = c['id'] as int;
    final visited = _visited.contains(id);
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: _selected.contains(id),
      onChanged: visited
          ? null
          : (on) => setState(() => on == true ? _selected.add(id) : _selected.remove(id)),
      title: Text('${c['name']}'),
      subtitle: Text(visited ? 'Visited on this day' : lastVisitLabel(c)),
      secondary: (c['status'] as String?) != null ? StatusBadge('${c['status']}') : null,
    );
  }
}
