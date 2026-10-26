import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/skeleton.dart';

/// What I have asked for that is still waiting, and who has to decide it, so I can ask them.
class MyPendingScreen extends StatefulWidget {
  const MyPendingScreen({super.key});

  @override
  State<MyPendingScreen> createState() => _MyPendingScreenState();
}

class _MyPendingScreenState extends State<MyPendingScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  static const _ink = Color(0xFF0F172A);
  static const _sub = Color(0xFF475569);

  static const _look = <String, (IconData, Color)>{
    'leaves': (Icons.beach_access_rounded, Color(0xFF0284C7)),
    'expenses': (Icons.receipt_long_rounded, Color(0xFFEA580C)),
    'allowances': (Icons.local_gas_station_rounded, Color(0xFF7C3AED)),
    'returns': (Icons.assignment_return_rounded, Color(0xFFDC2626)),
    'regularisation': (Icons.edit_calendar_rounded, Color(0xFF4F46E5)),
    'contacts': (Icons.storefront_rounded, Color(0xFF0D9488)),
    'access': (Icons.lock_open_rounded, Color(0xFF2563EB)),
    'handovers': (Icons.handshake_rounded, Color(0xFF0E9F6E)),
    'deposits': (Icons.account_balance_rounded, Color(0xFF0891B2)),
    'notes': (Icons.request_quote_rounded, Color(0xFFD97706)),
    'beats': (Icons.route_rounded, Color(0xFF9333EA)),
    'demands': (Icons.local_shipping_rounded, Color(0xFFF59E0B)),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = _data == null);
    try {
      final data = await Services.api.get('/api/v1/my-pending') as Map<String, dynamic>;
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

  List<Map<String, dynamic>> get _groups => ((_data?['groups'] as List?) ?? []).cast<Map<String, dynamic>>();

  Future<void> _call(String phone) => launchUrl(Uri.parse('tel:+$phone'));

  Future<void> _whatsApp(String phone, String text) =>
      launchUrl(Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);

  Widget _item(Map<String, dynamic> group, Map<String, dynamic> it) {
    final look = _look[group['key']] ?? (Icons.pending_actions_rounded, AppColors.primary);
    final who = (it['approver'] as Map?)?.cast<String, dynamic>();
    final phone = who?['phone'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 6, color: look.$2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: look.$2.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                    child: Icon(look.$1, color: look.$2, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${it['title']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: _ink))),
                  if (it['amount'] != null)
                    Text(fmtMoney(it['amount'] as num?, it['currency'] as String?), style: const TextStyle(fontWeight: FontWeight.w900, color: _ink)),
                ]),
                if ('${it['subtitle'] ?? ''}'.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text('${it['subtitle']}', style: const TextStyle(fontSize: 13, color: _sub))),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Sent ${fmtTime(it['date'])}', style: const TextStyle(fontSize: 12, color: _sub)),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.hourglass_top_rounded, size: 18, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Waiting for', style: TextStyle(fontSize: 11.5, color: _sub, fontWeight: FontWeight.w700)),
                        Text(who == null ? 'Your manager' : '${who['name']}${who['role'] != null ? ' · ${who['role']}' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: _ink)),
                      ]),
                    ),
                    if (phone != null) ...[
                      IconButton(
                        tooltip: 'Call',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.call_rounded, color: AppColors.success),
                        onPressed: () => _call(phone),
                      ),
                      IconButton(
                        tooltip: 'WhatsApp',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chat_rounded, color: Color(0xFF16A34A)),
                        onPressed: () => _whatsApp(phone, 'Hello ${who?['name'] ?? ''}, please look at my pending ${group['title']}: ${it['title']}.'),
                      ),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = (_data?['total'] as num?) ?? 0;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My pending requests')),
      body: _loading
          ? const LoadingView()
          : _error != null && _data == null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFEA580C), Color(0xFFF59E0B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: Text('$total', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(total == 0 ? 'Nothing pending' : 'Waiting for approval',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                              Text(total == 0 ? 'Everything you sent has been answered.' : 'Ask the person named on each one to decide it.',
                                  style: const TextStyle(color: Colors.white, fontSize: 13)),
                            ]),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      for (final g in _groups) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                          child: Text('${g['title']} (${g['count']})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: _ink)),
                        ),
                        for (final it in ((g['items'] as List?) ?? []).cast<Map<String, dynamic>>()) _item(g, it),
                      ],
                    ],
                  ),
                ),
    );
  }
}
