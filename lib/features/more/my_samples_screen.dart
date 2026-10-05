import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/member_picker.dart';
import '../../widgets/skeleton.dart';

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
  int _dir = 1;
  int _gen = 0;

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

  /// Slides a card in from below, a little later for each one down the list.
  Widget _enter(int index, Widget child) => TweenAnimationBuilder<double>(
        key: ValueKey('$_gen-$_tab-$index'),
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 380 + (index.clamp(0, 8) * 55)),
        curve: Curves.easeOutCubic,
        builder: (context, t, c) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * 22), child: c),
        ),
        child: child,
      );

  Widget _count(num v, TextStyle style) => TweenAnimationBuilder<double>(
        key: ValueKey('c$_gen-${v.toStringAsFixed(2)}'),
        tween: Tween(begin: 0, end: v.toDouble()),
        duration: const Duration(milliseconds: 750),
        curve: Curves.easeOutCubic,
        builder: (context, x, _) => Text(_n(x), style: style),
      );

  void _go(String code, List<String> order) {
    if (code == _tab) return;
    setState(() {
      _dir = order.indexOf(code) > order.indexOf(_tab) ? 1 : -1;
      _tab = code;
    });
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
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E63D6), Color(0xFF16A394)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: const Color(0xFF1E63D6).withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -18,
            child: Icon(Icons.science_rounded, size: 120, color: Colors.white.withValues(alpha: 0.09)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_member == 'me' ? 'IN MY HAND' : 'IN HAND',
                  style: const TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.4)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _count(inHand, const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 54, height: 1)),
                  const SizedBox(width: 8),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text('samples', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(children: [
                _heroStat(Icons.south_west_rounded, 'Taken', taken),
                const SizedBox(width: 10),
                _heroStat(Icons.north_east_rounded, 'Given', given),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(IconData icon, String label, num v) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Row(children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            _count(v, const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ]),
        ),
      );

  /// A pill that slides from tab to tab under the labels.
  Widget _tabs(List<(String, String)> tabs) {
    final order = [for (final t in tabs) t.$1];
    final at = order.indexOf(_tab).clamp(0, tabs.length - 1);
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFE9EEF7), borderRadius: BorderRadius.circular(18)),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / tabs.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            left: at * w,
            width: w,
            top: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.16), blurRadius: 12, offset: const Offset(0, 4))],
              ),
            ),
          ),
          Row(children: [
            for (final (code, label) in tabs)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _go(code, order),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: _tab == code ? AppColors.primary : AppColors.muted),
                      child: Text(label),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }

  Widget _empty(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          Icon(icon, size: 46, color: AppColors.muted.withValues(alpha: 0.45)),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(color: AppColors.muted)),
        ]),
      );

  /// One flavour, with a bar showing its share of what is in hand.
  Widget _product(Map r, num maxQty) {
    final q = (r['quantity'] as num?) ?? 0;
    final tint = q < 0 ? AppColors.danger : AppColors.success;
    final share = maxQty <= 0 ? 0.0 : (q.abs() / maxQty).clamp(0.0, 1.0).toDouble();
    final name = '${(r['product'] as Map)['name']}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _card,
      child: Row(children: [
        CircleAvatar(
          radius: 21,
          backgroundColor: tint.withValues(alpha: 0.12),
          child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
              style: TextStyle(color: tint, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              key: ValueKey('b$_gen-$_tab-$name'),
              tween: Tween(begin: 0, end: share),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: tint.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(tint),
                ),
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
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
          child: Icon(taken ? Icons.south_west_rounded : Icons.north_east_rounded, color: tint, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${m['product']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 2),
            Text(who,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
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
    final maxQty = onHand.fold<double>(
        0, (s, r) => ((r['quantity'] as num?) ?? 0).abs() > s ? ((r['quantity'] as num?) ?? 0).abs().toDouble() : s);
    final tabs = <(String, String)>[('hand', 'In hand'), if (team) ('people', 'By person') else ('moves', 'Movements')];
    final order = [for (final t in tabs) t.$1];
    if (!order.contains(_tab)) _tab = 'hand';

    Widget content() {
      var i = 0;
      final items = <Widget>[];
      if (_tab == 'hand') {
        if (onHand.isEmpty) items.add(_empty(Icons.inventory_2_outlined, 'Nothing in hand'));
        for (final r in onHand) {
          items.add(_enter(i++, _product(r, maxQty)));
        }
      } else if (_tab == 'people') {
        final people = ((d?['team'] as List?) ?? []).cast<Map>();
        if (people.isEmpty) items.add(_empty(Icons.groups_outlined, 'No team members'));
        for (final row in people) {
          items.add(_enter(i++, _person(row)));
        }
      } else {
        if (moves.isEmpty) items.add(_empty(Icons.swap_vert_rounded, 'No movements yet'));
        for (final m in moves) {
          items.add(_enter(i++, _move(m)));
        }
      }
      return Column(key: ValueKey('$_gen-$_tab'), crossAxisAlignment: CrossAxisAlignment.stretch, children: items);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_member == 'me' ? 'My Samples' : 'Samples'), centerTitle: false),
      body: d == null
          ? Center(
              child: _error != null
                  ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!))
                  : const LoadingView())
          : RefreshIndicator(
              onRefresh: () async {
                _gen++;
                await _load();
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(children: [
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
                                    _gen++;
                                  });
                                  _load();
                                },
                              ),
                            ),
                          ),
                        _hero(inHand, (d['taken'] as num?) ?? 0, (d['given'] as num?) ?? 0),
                        const SizedBox(height: 12),
                      ]),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _PinnedBar(
                      height: 66,
                      child: Container(
                        color: AppColors.background,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: _tabs(tabs),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                    sliver: SliverToBoxAdapter(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragEnd: (e) {
                          final v = e.primaryVelocity ?? 0;
                          if (v.abs() < 250) return;
                          final at = order.indexOf(_tab);
                          final next = v < 0 ? at + 1 : at - 1;
                          if (next >= 0 && next < order.length) _go(order[next], order);
                        },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 340),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.topCenter,
                            children: [...previous, if (current != null) current],
                          ),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(begin: Offset(0.12 * _dir, 0), end: Offset.zero).animate(anim),
                              child: child,
                            ),
                          ),
                          child: content(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _PinnedBar extends SliverPersistentHeaderDelegate {
  _PinnedBar({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(covariant _PinnedBar old) => true;
}
