import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/skeleton.dart';

/// The money the team has collected and still holds, and where each part has to go:
/// to the office (from distributors) or to a distributor (from its outlets).
class TeamCollectionsScreen extends StatefulWidget {
  const TeamCollectionsScreen({super.key});

  @override
  State<TeamCollectionsScreen> createState() => _TeamCollectionsScreenState();
}

class _TeamCollectionsScreenState extends State<TeamCollectionsScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  String _tab = 'person';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = _data == null);
    try {
      final data = await Services.api.get('/api/v1/team/collections') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _list(String key) => ((_data?[key] as List?) ?? []).cast<Map<String, dynamic>>();
  String? get _currency => _data?['currency'] as String?;
  String _money(num? v) => fmtMoney(v, _currency);
  static const _ink = Color(0xFF0F172A);
  static const _sub = Color(0xFF475569);

  Widget _hero() {
    final t = (_data?['totals'] as Map?)?.cast<String, dynamic>() ?? {};
    Widget tile(String label, num? v, IconData icon) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(height: 6),
              FittedBox(child: Text(_money(v), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17))),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF065F46), Color(0xFF059669), Color(0xFF0891B2)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: const Color(0xFF059669).withValues(alpha: 0.28), blurRadius: 20, offset: const Offset(0, 9))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Held by the team', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
        const SizedBox(height: 4),
        Text(_money(t['total'] as num?), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 32, height: 1.1)),
        const SizedBox(height: 12),
        Row(children: [
          tile('For the office', t['office'] as num?, Icons.apartment_rounded),
          tile('For distributors', t['distributors'] as num?, Icons.local_shipping_rounded),
        ]),
      ]),
    );
  }

  Widget _chip(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
      );

  Widget _line(String left, String right, {String? note, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(left, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w700, fontSize: 13.5, color: _ink)),
              if (note != null) Text(note, style: const TextStyle(fontSize: 11.5, color: _sub)),
            ]),
          ),
          Text(right, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: _ink)),
        ]),
      );

  Widget _person(Map<String, dynamic> m) {
    final e = m['employee'] as Map<String, dynamic>;
    final office = (m['office'] as num?) ?? 0;
    final dist = (m['distributor_total'] as num?) ?? 0;
    final from = ((m['office_from'] as List?) ?? []).cast<Map<String, dynamic>>();
    final dists = ((m['distributors'] as List?) ?? []).cast<Map<String, dynamic>>();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          shape: const RoundedRectangleBorder(),
          collapsedShape: const RoundedRectangleBorder(),
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text('${e['name']}'.isEmpty ? '?' : '${e['name']}'[0].toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
          ),
          title: Text('${e['name']}', style: const TextStyle(fontWeight: FontWeight.w900, color: _ink)),
          subtitle: Wrap(spacing: 6, runSpacing: 4, children: [
            if (office > 0) _chip('Office ${_money(office)}', AppColors.primary),
            if (dist > 0) _chip('Distributors ${_money(dist)}', AppColors.warning),
          ]),
          trailing: Text(_money(m['total'] as num?), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: _ink)),
          children: [
            if (from.isNotEmpty) ...[
              const Align(alignment: Alignment.centerLeft, child: Text('For the office', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary))),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(m['oldest'] != null ? 'Oldest ${fmtTime(m['oldest'])} · ${m['office_count']} collections' : '${m['office_count']} collections',
                    style: const TextStyle(fontSize: 11.5, color: _sub)),
              ),
              for (final f in from) _line('${(f['partner'] as Map)['name']}', _money(f['amount'] as num?), note: '${f['count']} collection(s) from this distributor'),
              const Divider(),
            ],
            for (final d in dists) ...[
              _line('For ${(d['distributor'] as Map)['name']}', _money(d['amount'] as num?), bold: true),
              for (final o in ((d['outlets'] as List?) ?? []).cast<Map<String, dynamic>>())
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: _line('• ${(o['outlet'] as Map)['name']}', _money(o['amount'] as num?),
                      note: '${o['count']} collection(s)${o['since'] != null ? ' · since ${fmtTime(o['since'])}' : ''}'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row({required IconData icon, required Color c, required String title, required String sub, required String amount}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: c, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: _ink)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _sub)),
            ]),
          ),
          Text(amount, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: _ink)),
        ]),
      );

  List<Widget> _body() {
    switch (_tab) {
      case 'distributor':
        final rows = _list('by_distributor');
        return [
          for (final r in rows)
            _row(
              icon: r['for'] == 'office' ? Icons.apartment_rounded : Icons.local_shipping_rounded,
              c: r['for'] == 'office' ? AppColors.primary : AppColors.warning,
              title: '${(r['distributor'] as Map)['name']}',
              sub: '${r['for'] == 'office' ? 'Collected from them, for the office' : 'Outlet money, for them'} · ${r['people']} ${r['people'] == 1 ? 'person' : 'people'}',
              amount: _money(r['amount'] as num?),
            ),
          if (rows.isEmpty) _empty(),
        ];
      case 'outlet':
        final rows = _list('by_outlet');
        return [
          for (final r in rows)
            _row(
              icon: Icons.storefront_rounded,
              c: AppColors.purple,
              title: '${(r['outlet'] as Map)['name']}',
              sub: 'For ${(r['distributor'] as Map)['name']} · ${r['people']} ${r['people'] == 1 ? 'person' : 'people'}',
              amount: _money(r['amount'] as num?),
            ),
          if (rows.isEmpty) _empty(),
        ];
      default:
        final rows = _list('members');
        return [for (final m in rows) _person(m), if (rows.isEmpty) _empty()];
    }
  }

  Widget _empty() => const Padding(
      padding: EdgeInsets.all(32), child: Center(child: Text('The team holds no money right now.', style: TextStyle(color: _sub))));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Collections in hand')),
      body: _loading
          ? const LoadingView()
          : _error != null && _data == null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                    children: [
                      _hero(),
                      const SizedBox(height: 14),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'person', label: Text('By person')),
                          ButtonSegment(value: 'distributor', label: Text('By distributor')),
                          ButtonSegment(value: 'outlet', label: Text('By outlet')),
                        ],
                        selected: {_tab},
                        onSelectionChanged: (v) => setState(() => _tab = v.first),
                      ),
                      const SizedBox(height: 12),
                      ..._body(),
                    ],
                  ),
                ),
    );
  }
}
