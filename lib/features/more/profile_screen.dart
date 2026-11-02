import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/photos.dart';
import '../../core/security_guard.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/avatar.dart';
import '../../core/models.dart';
import '../../widgets/common.dart';
import '../../widgets/sdk_map.dart';
import '../../widgets/sync_status.dart';
import '../auth/login_screen.dart';
import '../auth/password_screens.dart';

/// Role-based gradient colours as requested by client:
/// 1. Stock & Despatch Coordinator [Nesto], Sales Representative & Merchandiser,
///    Sales Representative, Sales Officer, Brand Promoter, Brand Activation & Collaboration Executive:
///    #38D9C0 -> #0B5FA5
/// 2. Senior Sales Officer, Sales Team Lead:
///    #7ED957 -> #00796B
/// 3. Sales Operations Manager, Asst Manager – Sales & Marketing:
///    #F44336 -> #7F0000
/// 4. Manager – Central Kerala:
///    #B794F4 -> #44208F
/// 5. Growth Officer, Growth Manager – Bangalore, Growth Manager:
///    #FFC000 -> #E65100
/// 6. HR Officer:
///    #FF8AF0 -> #A0148C
(Color, Color) designationGradient(String? designation) {
  if (designation == null || designation.trim().isEmpty) {
    return (const Color(0xFF38D9C0), const Color(0xFF0B5FA5));
  }
  final raw = designation.toLowerCase().trim();
  final norm = raw
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll(RegExp(r'\[.*?\]|\(.*?\)' ), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // Group 6: HR Officer (#FF8AF0 -> #A0148C)
  if (norm.contains('hr officer') || norm == 'hr' || norm.contains('human resources')) {
    return (const Color(0xFFFF8AF0), const Color(0xFFA0148C));
  }

  // Group 5: Growth Officer, Growth Manager – Bangalore, Growth Manager (#FFC000 -> #E65100)
  if (norm.contains('growth')) {
    return (const Color(0xFFFFC000), const Color(0xFFE65100));
  }

  // Group 4: Manager – Central Kerala (#B794F4 -> #44208F)
  if (norm.contains('central kerala')) {
    return (const Color(0xFFB794F4), const Color(0xFF44208F));
  }

  // Group 3: Sales Operations Manager, Asst Manager – Sales & Marketing (#F44336 -> #7F0000)
  if (norm.contains('sales operations') ||
      norm.contains('operations manager') ||
      norm.contains('asst manager') ||
      norm.contains('assistant manager') ||
      norm.contains('sales & marketing') ||
      norm.contains('sales and marketing')) {
    return (const Color(0xFFF44336), const Color(0xFF7F0000));
  }

  // Group 2: Senior Sales Officer, Sales Team Lead (#7ED957 -> #00796B)
  if (norm.contains('senior sales officer') ||
      norm.contains('sales team lead') ||
      norm.contains('team lead')) {
    return (const Color(0xFF7ED957), const Color(0xFF00796B));
  }

  // Group 1: Stock & Despatch Coordinator [Nesto], Sales Representative & Merchandiser,
  // Sales Representative, Sales Officer, Brand Promoter, Brand Activation & Collaboration Executive (#38D9C0 -> #0B5FA5)
  if (norm.contains('stock') ||
      norm.contains('despatch') ||
      norm.contains('dispatch') ||
      norm.contains('merchandiser') ||
      norm.contains('sales representative') ||
      norm.contains('sales officer') ||
      norm.contains('brand promoter') ||
      norm.contains('promoter') ||
      norm.contains('activation') ||
      norm.contains('coordinator') ||
      norm.contains('executive')) {
    return (const Color(0xFF38D9C0), const Color(0xFF0B5FA5));
  }

  return (const Color(0xFF38D9C0), const Color(0xFF0B5FA5));
}

const _scopeLabels = {
  'own': 'Own records',
  'hierarchy': 'Team reporting to me',
  'team': 'My field team',
  'all': 'All employees',
};

/// Who is logged in, what they are responsible for, and the way out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// Teams, territories, beats, details and the company, from the server.
  Map<String, dynamic>? _info;

  @override
  void initState() {
    super.initState();
    _peekCached();
    _loadInfo();
  }

  Future<void> _peekCached() async {
    try {
      final cached = await Services.api.peek('/api/v1/me/profile-details');
      if (cached is Map && mounted && _info == null) {
        setState(() => _info = Map<String, dynamic>.from(cached));
      }
    } catch (_) {}
  }

  Future<void> _loadInfo() async {
    try {
      final data = await Services.api.get('/api/v1/me/profile-details');
      if (data is Map && mounted) {
        setState(() => _info = Map<String, dynamic>.from(data));
      }
    } catch (_) {
      // Without it the page shows what the app already knows.
    }
  }

  List<Map<String, dynamic>> _list(String key) {
    final raw = _info?[key];
    if (raw is List) {
      return raw.map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList();
    }
    return [];
  }

  Map<String, dynamic> _map(String key) {
    final raw = _info?[key];
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  Color _hex(String? value, Color fallback) {
    final v = (value ?? '').replaceAll('#', '');
    final n = int.tryParse(v, radix: 16);
    return v.length == 6 && n != null ? Color(0xFF000000 | n) : fallback;
  }

  Future<void> _logout(BuildContext context) async {
    await Services.outbox.flush();
    final unsent = Services.outbox.pending.value + Services.outbox.failed.value;
    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: Text(unsent == 0
            ? 'Tracking stops and unsent locations are uploaded first.'
            : '$unsent action${unsent == 1 ? ' has' : 's have'} not reached the server yet and will be lost. '
                'Connect to the internet and wait for them to sync first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirm != true) return;
    await Services.tracker.stop();
    Services.outbox.stop();
    SecurityGuard.instance.stop();
    await Services.queue.clearCache();
    await Services.auth.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final profile = Services.auth.profile!;
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _hero(profile),
          const SizedBox(height: 12),
          _listButtons(),
          const SizedBox(height: 12),
          _details(profile),
          const SizedBox(height: 12),
          _company(),
          // Working Hours sit in Employee Details now, instead of a shift card.
          _permissions(profile),
          const SizedBox(height: 12),
          const Card(
            margin: EdgeInsets.zero,
            child: Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: SyncStatusBar()),
          ),
          const SizedBox(height: 12),
          _settingsEntry(profile),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
            icon: const Icon(Icons.lock_reset_rounded),
            label: const Text('Change password'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 12),
          GradientButton(
            label: 'Log out',
            icon: Icons.logout_rounded,
            gradient: AppColors.dangerGradient,
            onPressed: () => _logout(context),
          ),
        ],
      ),
    );
  }

  (Color, Color) _heroGradient(Profile profile) {
    final des = _info?['designation'] ?? profile.designation;
    final colour = _map('colour');
    final sStr = colour['start'] as String?;
    final eStr = colour['end'] as String?;
    if (sStr != null && eStr != null && sStr.isNotEmpty && eStr.isNotEmpty) {
      final s = _hex(sStr, Colors.transparent);
      final e = _hex(eStr, Colors.transparent);
      if (s != Colors.transparent && e != Colors.transparent) {
        return (s, e);
      }
    }
    return designationGradient(des);
  }

  Widget _hero(Profile profile) {
    final (start, end) = _heroGradient(profile);
    final active = '${_info?['status'] ?? 'Active'}' == 'Active';
    final designation = _info?['designation'] ?? profile.designation;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [start, end]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _ChangeablePhoto(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(profile.name.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 8),
                    _badge(active),
                  ],
                ),
                // The Field Employee Code, right under the name.
                if (profile.code != null && profile.code!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('Employee ID: ${profile.code}',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                ],
                if (designation != null && '$designation'.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('$designation',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xF2FFFFFF), fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(bool active) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 7, color: active ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
            const SizedBox(width: 5),
            Text(active ? 'Active' : 'Inactive',
                style: TextStyle(
                    color: active ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );

  /// Team, Territory and Beats: each is a button that opens its full list.
  Widget _listButtons() {
    var teams = _list('teams');
    final territoriesMap = _map('territories');
    List<Map<String, dynamic>> subList(String k) {
      final raw = territoriesMap[k];
      if (raw is List) {
        return raw.map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList();
      }
      return [];
    }
    final primary = subList('primary');
    final secondary = subList('secondary');
    final outside = subList('outside');
    var beats = _list('beats');
    final profile = Services.auth.profile!;

    // Fallbacks if server hasn't returned yet or fields were missing
    if (teams.isEmpty && profile.team != null && profile.team!.trim().isNotEmpty) {
      teams = [
        {'name': profile.team!, 'lead': profile.manager ?? '-', 'members': 1},
      ];
    }
    if (beats.isEmpty && profile.routes.isNotEmpty) {
      beats = [
        for (final r in profile.routes)
          {'name': r.name, 'outlets': 0, 'city': null, 'state': 'approved'},
      ];
    }

    String count(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    Widget cell(IconData icon, String title, String value, Color tint, VoidCallback onTap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Icon(icon, size: 22, color: tint),
                  const SizedBox(height: 6),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                ],
              ),
            ),
          ),
        );
    // "Team" is now "Region": the region's name, and a page with its districts and my territories in it.
    final region = _map('region');
    final regionName = asText(region['name']) ?? (teams.isEmpty ? null : asText(teams.first['name']));
    final mine = [
      for (final t in primary) (t, 'Primary'),
      for (final t in secondary) (t, 'Secondary'),
      for (final t in outside) (t, 'Outside'),
    ];
    return Row(
      children: [
        cell(Icons.public_rounded, 'Region', regionName ?? '—', AppColors.primary,
            () => _openRegion(regionName, region, mine)),
        const SizedBox(width: 10),
        cell(Icons.place_rounded, 'Territory',
            count(primary.length + secondary.length + outside.length, 'territory', 'territories'), AppColors.success,
            () => _openList('My Territories', 'Opened by tapping “Territory”', null, [
                  if (primary.isNotEmpty)
                    ('Primary territory', [for (final t in primary) ('${t['name']}', '${t['region'] ?? ''}', 'Primary')]),
                  if (secondary.isNotEmpty)
                    ('Secondary territory', [for (final t in secondary) ('${t['name']}', '${t['region'] ?? ''}', 'Secondary')]),
                  if (outside.isNotEmpty)
                    ('Outside territory', [for (final t in outside) ('${t['name']}', '${t['region'] ?? ''}', 'Outside')]),
                ])),
        const SizedBox(width: 10),
        cell(Icons.route_rounded, profile.routeLabel == 'Beat' ? 'Beats' : '${profile.routeLabel}s',
            count(beats.length, 'beat', 'beats'), AppColors.warning,
            () => _openList('My Beats', 'Opened by tapping “Beats”', Icons.calendar_month_rounded, [
                  (null, [
                    for (final b in beats)
                      (
                        '${b['name']}',
                        '${b['outlets']} outlets${b['city'] != null ? ' · ${b['city']}' : ''}',
                        b['state'] == 'pending' ? 'Pending approval' : 'Approved',
                      ),
                  ]),
                ])),
      ],
    );
  }

  /// My Region: the region with its districts and territories, then my own territories in it, each marked
  /// Primary, Secondary or Outside.
  void _openRegion(String? name, Map<String, dynamic> region, List<(Map<String, dynamic>, String)> mine) {
    List<String> names(dynamic raw) => raw is List
        ? [for (final e in raw) if ((e is Map ? asText(e['name']) : asText(e)) != null) (e is Map ? '${e['name']}' : '$e')]
        : const [];
    // Without the server's lists, they are read off my own territories (each carries its district).
    var districts = names(region['districts']);
    if (districts.isEmpty) districts = {for (final (t, _) in mine) if (asText(t['region']) != null) '${t['region']}'}.toList();
    var territories = names(region['territories']);
    if (territories.isEmpty) territories = [for (final (t, _) in mine) '${t['name']}'];
    const blue = Color(0xFF1A56DB);
    Color pill(String kind) => switch (kind) {
          'Primary' => blue,
          'Secondary' => AppColors.purple,
          _ => AppColors.warning,
        };
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 92, child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted))),
            Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ),
          ]),
        );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('My Region', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
            Text('Opened by tapping “Region”',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
          ]),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name ?? 'Region not set', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 4),
              line('Districts', districts.join(', ')),
              line('Territories', territories.join(', ')),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 16, 2, 8),
            child: Text('Your territories in this region',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: blue)),
          ),
          if (mine.isEmpty) const Text('No territory is assigned to you yet.', style: TextStyle(color: AppColors.muted)),
          for (final (t, kind) in mine)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    if (asText(t['region']) != null)
                      Text('${t['region']}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: pill(kind).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                  child: Text(kind, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: pill(kind))),
                ),
              ]),
            ),
        ]),
      ),
    ));
  }

  /// A list page: a title with a line under it, then groups (each with an optional heading) of rows: a name,
  /// a line under it and a small status pill on the right.
  void _openList(String title, String subtitle, IconData? icon, List<(String?, List<(String, String, String?)>)> groups) {
    const blue = Color(0xFF1A56DB);
    Color badge(String status) => switch (status) {
          'Primary' => blue,
          'Secondary' => AppColors.purple,
          'Outside' || 'Pending approval' => AppColors.warning,
          _ => AppColors.success,
        };
    final empty = groups.every((g) => g.$2.isEmpty);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
            Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
          ]),
        ),
        body: empty
            ? const Center(child: Text('Nothing here yet.', style: TextStyle(color: AppColors.muted)))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  for (final group in groups) ...[
                    if (group.$1 != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
                        child: Text(group.$1!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: blue)),
                      ),
                    for (final row in group.$2)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            if (icon != null) ...[
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(color: blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                                child: Icon(icon, color: blue, size: 21),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(row.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                                  if (row.$2.isNotEmpty)
                                    Text(row.$2, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                ],
                              ),
                            ),
                            if (row.$3 != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: badge(row.$3!).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(row.$3!,
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: badge(row.$3!))),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
      ),
    ));
  }

  Widget _section({required IconData icon, required String title, Widget? action, required List<Widget> children}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                ),
                if (action != null) action,
              ],
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, {Color tint = AppColors.primary, bool last = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration:
                    BoxDecoration(color: tint.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, size: 17, color: tint),
              ),
              const SizedBox(width: 10),
              // The label keeps only the room it needs; the value gets all the rest.
              Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(value,
                    textAlign: TextAlign.right,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ],
          ),
          if (!last) ...[
            const SizedBox(height: 9),
            Container(height: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }

  String _formatWebsite(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return 'www.kumbayah.in';
    }
    var clean = raw.trim().toLowerCase();
    clean = clean.replaceFirst(RegExp(r'^https?:\/\/'), '');
    clean = clean.replaceFirst(RegExp(r'\/$'), '');
    return clean.isEmpty ? 'www.kumbayah.in' : clean;
  }

  /// A row whose label is in [links] opens that address when tapped.
  Widget _infoCard({required String title, required List<(String, String)> rows, Map<String, String> links = const {}}) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0F1B3D)),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    rows[i].$1,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: links.containsKey(rows[i].$1)
                        ? InkWell(
                            onTap: () => launchUrl(Uri.parse(links[rows[i].$1]!), mode: LaunchMode.externalApplication),
                            child: Text(
                              rows[i].$2,
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: Color(0xFF1D4ED8),
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          )
                        : Text(
                            rows[i].$2,
                            textAlign: TextAlign.right,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: Color(0xFF0F1B3D),
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "9 hrs": the server's working hours, else the length of the shift.
  String? _workingHours(Profile profile, Map<String, dynamic> d) {
    final raw = d['working_hours'];
    num? hours = raw is num ? raw : num.tryParse('${raw ?? ''}'.replaceAll(RegExp(r'[^0-9.]'), ''));
    final start = profile.shiftStart, end = profile.shiftEnd;
    if (hours == null && start != null && end != null) hours = end >= start ? end - start : end + 24 - start;
    if (hours == null || hours <= 0) return null;
    return '${fmtQty(hours)} hrs';
  }

  /// Reports to, department and working hours (shown instead of a shift).
  Widget _details(Profile profile) {
    final d = _map('details');
    final rows = <(String, String?)>[
      ('Reports to', (d['reports_to'] as String?) ?? profile.manager),
      ('Department', d['department'] as String?),
      ('Working Hours', _workingHours(profile, d)),
    ].where((row) => (row.$2 ?? '').isNotEmpty).map((row) => (row.$1, row.$2!)).toList();
    return _infoCard(
      title: 'Employee Details',
      rows: rows,
    );
  }

  /// The company the person works for: the full GSTIN, and a website and Instagram that open when tapped.
  Widget _company() {
    final c = _map('company');
    final name = (c['name'] as String?)?.trim();
    final companyName = (name != null && name.isNotEmpty) ? name : 'Kumbayah Foods Private Limited';
    final gstin = ((c['gstin'] as String?) ?? '').trim().toUpperCase();

    String withScheme(String raw) => raw.startsWith('http://') || raw.startsWith('https://') ? raw : 'https://$raw';
    final webRaw = ((c['website'] as String?) ?? '').trim();
    final instaRaw = ((c['instagram'] as String?) ?? '').trim();
    final links = <String, String>{};
    if (webRaw.isNotEmpty) links['Website'] = withScheme(webRaw);
    String? handle;
    if (instaRaw.isNotEmpty) {
      handle = instaRaw.contains('instagram.com/')
          ? instaRaw.split('instagram.com/').last.split('?').first.replaceAll('/', '').trim()
          : instaRaw.replaceAll('@', '').replaceAll('/', '').trim();
      links['Instagram'] = instaRaw.contains('instagram.com/') ? withScheme(instaRaw) : 'https://www.instagram.com/$handle/';
    }

    final rows = <(String, String)>[
      ('Company', companyName),
      if (gstin.isNotEmpty) ('GSTIN', gstin),
      if (webRaw.isNotEmpty) ('Website', _formatWebsite(webRaw)),
      if (handle != null && handle.isNotEmpty) ('Instagram', '@$handle'),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _infoCard(title: 'Company Details', rows: rows, links: links),
    );
  }


  /// The way to the maps and app details, kept out of the profile itself.
  Widget _settingsEntry(Profile profile) => Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Settings')),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _maps(profile),
                  const SizedBox(height: 12),
                  _appInfo(),
                ],
              ),
            ),
          )),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.settings_rounded, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Settings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                      Text('Maps, app version and server',
                          style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      );

  static const _mapModes = {
    'sdk': 'Google map inside the app (free)',
    'google': 'Google everywhere (billed)',
    'open': 'Open maps everywhere (free)',
    'hybrid': 'Google maps, free addresses',
  };

  Widget _maps(Profile profile) {
    final mode = _mapModes[profile.mapMode] ?? profile.mapMode;
    final sdkReady = SdkMap.available;
    return _section(
      icon: Icons.map_rounded,
      title: 'Maps',
      children: [
        _row(Icons.layers_rounded, 'Chosen in Odoo', mode),
        _row(Icons.vpn_key_rounded, 'Google key sent by Odoo', profile.googleMapsKey.isEmpty ? 'No' : 'Yes'),
        _row(Icons.build_circle_rounded, 'Key built into this app', SdkMap.builtWithKey ? 'Yes' : 'No'),
        _row(
          sdkReady ? Icons.verified_rounded : Icons.public_rounded,
          'This phone is using',
          sdkReady ? "Google's own map" : 'The free map',
          tint: sdkReady ? AppColors.success : AppColors.muted,
          last: true,
        ),
      ],
    );
  }

  Widget _permissions(Profile profile) => _section(
        icon: Icons.verified_user_rounded,
        title: 'Permissions',
        children: [
          _row(Icons.visibility_rounded, 'Data access', _scopeLabels[profile.scope] ?? profile.scope,
              last: true),
        ],
      );

  Widget _appInfo() => _section(
        icon: Icons.phone_android_rounded,
        title: 'App Information',
        children: [
          FutureBuilder(
            future: Future.wait([PackageInfo.fromPlatform(), Services.api.url('')]),
            builder: (context, snapshot) {
              final info = snapshot.data?[0] as PackageInfo?;
              final server = snapshot.data?[1] as String?;
              return Column(
                children: [
                  _row(Icons.settings_rounded, 'App version',
                      info == null ? '…' : '${info.version} (${info.buildNumber})'),
                  _row(Icons.dns_rounded, 'Server', server ?? '…', last: true),
                ],
              );
            },
          ),
        ],
      );
}

/// The profile photo; tap to take a new one or pick from the gallery.
class _ChangeablePhoto extends StatefulWidget {
  const _ChangeablePhoto();

  @override
  State<_ChangeablePhoto> createState() => _ChangeablePhotoState();
}

class _ChangeablePhotoState extends State<_ChangeablePhoto> {
  bool _busy = false;

  Future<void> _change() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheet, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheet, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final bytes = await takePhoto(source, selfie: true, stamp: false);
    if (bytes == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await Services.api.post('/api/v1/me/photo', {'image': base64Encode(bytes)});
      await Services.auth.refreshProfile();
      settleAndRefresh();
      if (mounted) showSnack(context, 'Photo updated');
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _busy ? null : _change,
      child: Stack(
        children: [
          MyAvatar(key: ValueKey(Services.auth.profile?.photoVersion), size: 68, border: true),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: _busy
                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
