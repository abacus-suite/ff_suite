import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/member_picker.dart';

/// Samples in hand: what was taken, what was given away and what is left,
/// for me or (a manager) for a teammate or the whole team.
class MySamplesScreen extends StatefulWidget {
  const MySamplesScreen({super.key});

  @override
  State<MySamplesScreen> createState() => _MySamplesScreenState();
}

class _MySamplesScreenState extends State<MySamplesScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  String _member = 'me';
  String _tab = 'hand';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Services.api.get('/api/v1/field-tasks/samples', query: {'member': _member})
          as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  static String _n(num? v) {
    final x = (v ?? 0).toDouble();
    return x == x.roundToDouble() ? '${x.toInt()}' : x.toStringAsFixed(1);
  }

  static String _day(dynamic iso) {
    final d = DateTime.tryParse('$iso')?.toLocal();
    if (d == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  BoxDecoration get _card => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.07), blurRadius: 18, offset: const Offset(0, 6))],
      );

  Widget _hero(num inHand, num taken, num given) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E63D6), Color(0xFF16A394)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: const Color(0xFF1E63D6).withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.science_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Text(_member == 'me' ? 'In my hand' : 'In hand',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 10),
          Text(_n(inHand),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 46, height: 1)),
          const Text('samples', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          Row(children: [
            _heroStat(Icons.south_west_rounded, 'Taken', taken),
            const SizedBox(width: 10),
            _heroStat(Icons.north_east_rounded, 'Given', given),
          ]),
        ],
      ),
    );
  }

  Widget _heroStat(IconData icon, String label, num v) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(_n(v), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ]),
        ),
      );

  Widget _tabs(bool team) {
    final tabs = <(String, String)>[
      ('hand', 'In hand'),
      if (team) ('people', 'By person') else ('moves', 'Movements'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        for (final (code, label) in tabs)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = code),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _tab == code ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _tab == code
                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))]
                      : null,
                ),
                child: Center(
                  child: Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: _tab == code ? AppColors.primary : AppColors.muted)),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _empty(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(children: [
          Icon(icon, size: 44, color: AppColors.muted.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(color: AppColors.muted)),
        ]),
      );

  /// One flavour, with a bar showing its share of what is in hand.
  Widget _product(Map r, num maxQty) {
    final q = (r['quantity'] as num?) ?? 0;
    final neg = q < 0;
    final tint = neg ? AppColors.danger : AppColors.success;
    final share = maxQty <= 0 ? 0.0 : (q.abs() / maxQty).clamp(0.0, 1.0).toDouble();
    final name = '${(r['product'] as Map)['name']}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _card,
      child: Row(children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: tint.withValues(alpha: 0.12),
          child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
              style: TextStyle(color: tint, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 6,
                backgroundColor: tint.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(tint),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 14),
        Text(_n(q), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: tint)),
      ]),
    );
  }

  Widget _move(Map m) {
    final taken = m['direction'] == 'in';
    final tint = taken ? AppColors.sky : AppColors.purple;
    final who = taken
        ? 'From ${m['source_type'] ?? ''}${m['contact'] != null ? ' · ${m['contact']}' : ''}'
        : 'To ${m['contact'] ?? 'a contact'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: _card,
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
          child: Icon(taken ? Icons.south_west_rounded : Icons.north_east_rounded, color: tint, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${m['product']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 2),
            Text(who, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${taken ? '+' : '−'}${_n(m['quantity'] as num?)}',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: tint)),
          Text(_day(m['date']), style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
        ]),
      ]),
    );
  }

  Widget _person(Map row) {
    final onHand = (row['on_hand'] as List).cast<Map>();
    final total = onHand.fold<double>(0, (s, r) => s + ((r['quantity'] as num?) ?? 0));
    final name = '${(row['employee'] as Map)['name']}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _card,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900)),
          ),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('Taken ${_n(row['taken'] as num?)} · Given ${_n(row['given'] as num?)}',
              style: const TextStyle(fontSize: 12)),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_n(total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.success)),
            const Text('in hand', style: TextStyle(fontSize: 11, color: AppColors.muted)),
          ]),
          children: [
            if (onHand.isEmpty)
              const Padding(padding: EdgeInsets.all(8), child: Text('Nothing in hand', style: TextStyle(color: AppColors.muted))),
            for (final r in onHand)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(child: Text('${(r['product'] as Map)['name']}')),
                  Text(_n(r['quantity'] as num?), style: const TextStyle(fontWeight: FontWeight.w900)),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final team = d?['team'] is List;
    final onHand = ((d?['on_hand'] as List?) ?? []).cast<Map>();
    final moves = ((d?['moves'] as List?) ?? []).cast<Map>();
    final inHand = onHand.fold<double>(0, (s, r) => s + ((r['quantity'] as num?) ?? 0));
    final maxQty = onHand.fold<double>(0, (s, r) => ((r['quantity'] as num?) ?? 0).abs() > s ? ((r['quantity'] as num?) ?? 0).abs().toDouble() : s);
    if (team && _tab == 'moves') _tab = 'hand';
    if (!team && _tab == 'people') _tab = 'hand';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_member == 'me' ? 'My Samples' : 'Samples'), centerTitle: false),
      body: d == null
          ? Center(child: _error != null ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!)) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: [
                  if (Services.auth.profile?.isManager ?? false)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: MemberPicker(
                          value: _member,
                          onChanged: (v) {
                            setState(() {
                              _member = v;
                              _data = null;
                            });
                            _load();
                          },
                        ),
                      ),
                    ),
                  _hero(inHand, (d['taken'] as num?) ?? 0, (d['given'] as num?) ?? 0),
                  const SizedBox(height: 16),
                  _tabs(team),
                  const SizedBox(height: 14),
                  if (_tab == 'hand') ...[
                    if (onHand.isEmpty) _empty(Icons.inventory_2_outlined, 'Nothing in hand'),
                    for (final r in onHand) _product(r, maxQty),
                  ] else if (_tab == 'people') ...[
                    if ((d['team'] as List).isEmpty) _empty(Icons.groups_outlined, 'No team members'),
                    for (final row in (d['team'] as List).cast<Map>()) _person(row),
                  ] else ...[
                    if (moves.isEmpty) _empty(Icons.swap_vert_rounded, 'No movements yet'),
                    for (final m in moves) _move(m),
                  ],
                ],
              ),
            ),
    );
  }
}
