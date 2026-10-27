import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'added_visits.dart';

/// Add a Visit: tick one or more outlets or distributors that are not in today's beat, nearest first,
/// and add them to today. Only the client is chosen - nothing else. Returns true when something was added.
class AddVisitScreen extends StatefulWidget {
  const AddVisitScreen({super.key, this.skipIds = const {}});

  /// Already in today's beat (planned, added or visited): not offered again.
  final Set<Object?> skipIds;

  @override
  State<AddVisitScreen> createState() => _AddVisitScreenState();
}

class _AddVisitScreenState extends State<AddVisitScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _clients = [];
  final Map<Object?, Map<String, dynamic>> _picked = {};
  Position? _here;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _here ??= await currentPosition(recentOk: true)
          .timeout(const Duration(seconds: 12))
          .then<Position?>((p) => p, onError: (_) => lastKnownPosition());
      final q = _search.text.trim();
      final here = _here;
      final data = await Services.api.get('/api/v1/clients', query: {
        'limit': 100,
        if (q.isNotEmpty) 'q': q,
        if (here != null) 'lat': here.latitude,
        if (here != null) 'lng': here.longitude,
        // Without a search the list is what is close by; a search looks everywhere.
        if (here != null && q.isEmpty) 'radius_km': 25,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _clients = ((data['clients'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  /// Outlets and distributors only: a lead is not visited from here.
  static bool _visitable(Map<String, dynamic> c) => '${c['category_type'] ?? ''}'.toLowerCase() != 'lead';

  Future<void> _addToToday() async {
    if (_picked.isEmpty) return;
    setState(() => _busy = true);
    await AddedVisits.add(_picked.values.toList());
    // Saved in today's plan too, as planned stops: they then count in the day's summary and the Next Visit
    // suggestion. Offline or on an older server the list kept on the phone still shows them.
    try {
      await Services.api.post('/api/v1/route-plan/add-visit', {'partner_ids': _picked.keys.toList()});
    } catch (_) {}
    if (!mounted) return;
    showSnack(context, _picked.length == 1 ? 'Added to today\'s beat' : '${_picked.length} added to today\'s beat');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final rows = nearestFirst(
      _clients.where((c) => _visitable(c) && !widget.skipIds.contains(c['id'])).toList(),
      _here,
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add a Visit', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          Text('Choose the client – nothing else',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: GradientButton(
            label: _picked.length > 1 ? 'Add ${_picked.length} to today\'s beat' : 'Add to today\'s beat',
            busy: _busy,
            onPressed: _picked.isEmpty || _busy ? null : _addToToday,
          ),
        ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search outlet / distributor…',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _error != null && _clients.isEmpty
              ? ErrorView(message: _error!, onRetry: _load)
              : rows.isEmpty && !_loading
                  ? const EmptyView(icon: Icons.storefront_rounded, text: 'No outlet to add here.\nTry a search.')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: rows.length,
                      itemBuilder: (_, i) => _row(rows[i]),
                    ),
        ),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> c) {
    final on = _picked.containsKey(c['id']);
    final area = asText((c['district'] as Map?)?['name']) ?? asText(c['address']);
    final metres = metresTo(_here, c);
    final detail = [if (area != null) area, if (metres != null) fmtDistance(metres)].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: CheckboxListTile(
        value: on,
        controlAffinity: ListTileControlAffinity.leading,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onChanged: (v) => setState(() => v == true ? _picked[c['id']] = c : _picked.remove(c['id'])),
        title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: detail.isEmpty ? null : Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
