import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

  /// "9:30 AM - 6:30 PM" from the shift's two numbers.
  String? get _shiftHours {
    final profile = Services.auth.profile!;
    final start = profile.shiftStart;
    final end = profile.shiftEnd;
    if (start == null || end == null) return null;
    String clock(double value) {
      final hours = value.floor();
      final minutes = ((value - hours) * 60).round();
      final hour12 = hours % 12 == 0 ? 12 : hours % 12;
      return '$hour12:${minutes.toString().padLeft(2, '0')} ${hours < 12 ? 'AM' : 'PM'}';
    }

    return '${clock(start)} - ${clock(end)}';
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
          _work(profile),
          _permissions(profile),
          const SizedBox(height: 12),
          const Card(
            margin: EdgeInsets.zero,
            child: Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: SyncStatusBar()),
          ),
          const SizedBox(height: 12),
          _settingsEntry(profile),
          const SizedBox(height: 14),
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
    return Row(
      children: [
        cell(Icons.groups_2_rounded, 'Region', count(teams.length, 'region', 'regions'), AppColors.primary,
            () => _openList('My Region', 'Opened by tapping “Region”', Icons.groups_2_rounded, [
                  (null, [
                    for (final t in teams)
                      ('${t['name']}', 'Lead: ${t['lead'] ?? '-'} · ${t['members']} members', null),
                  ]),
                ])),
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

  String _formatGst(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return '32XXXXXXXXXXXZX';
    }
    final clean = raw.trim().toUpperCase().replaceAll(' ', '');
    if (clean.contains('X') || clean.contains('*')) {
      return clean.replaceAll('*', 'X');
    }
    if (clean.length >= 4) {
      final prefix = clean.substring(0, 2);
      final suffix = clean.substring(clean.length - 2);
      final maskLen = clean.length - 4;
      return '$prefix${'X' * maskLen}$suffix';
    }
    return '32XXXXXXXXXXXZX';
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

  String _formatInstagram(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return '@kumbayah';
    }
    var clean = raw.trim();
    if (clean.contains('instagram.com/')) {
      clean = clean.split('instagram.com/').last.split('?').first.replaceAll('/', '').trim();
    }
    if (clean.startsWith('@')) return clean;
    return clean.isEmpty ? '@kumbayah' : '@$clean';
  }

  Widget _infoCard({required String title, required List<(String, String)> rows}) {
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
                    child: Text(
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

  Widget _details(Profile profile) {
    final d = _map('details');
    final rows = <(String, String?)>[
      ('Reports to', (d['reports_to'] as String?) ?? profile.manager),
      ('Department', d['department'] as String?),
      ('Employee ID', (d['employee_id'] as String?) ?? profile.code),
    ].where((row) => (row.$2 ?? '').isNotEmpty).map((row) => (row.$1, row.$2!)).toList();
    return _infoCard(
      title: 'Employee Details',
      rows: rows,
    );
  }

  /// The company the person works for.
  Widget _company() {
    final c = _map('company');
    final name = (c['name'] as String?)?.trim();
    final companyName = (name != null && name.isNotEmpty) ? name : 'Kumbayah Foods Pvt Ltd';
    final gstin = _formatGst(c['gstin'] as String?);
    final website = _formatWebsite(c['website'] as String?);
    final instagram = _formatInstagram(c['instagram'] as String?);

    final rows = <(String, String)>[
      ('Company', companyName),
      ('GSTIN', gstin),
      ('Website', website),
      ('Instagram', instagram),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _infoCard(
        title: 'Company Details',
        rows: rows,
      ),
    );
  }

  Widget _work(Profile profile) {
    final hours = _shiftHours;
    if (profile.shiftName == null && hours == null) return const SizedBox.shrink();
    final rows = <(IconData, String, String)>[
      (Icons.access_time_filled_rounded, 'Shift', profile.shiftName ?? 'Not set'),
      if (hours != null) (Icons.schedule_rounded, 'Working hours', hours),
      (Icons.place_rounded, 'Work type', 'Field work'),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _section(
        icon: Icons.schedule_rounded,
        title: 'Work Information',
        children: [
          for (final (i, row) in rows.indexed)
            _row(row.$1, row.$2, row.$3, tint: AppColors.purple, last: i == rows.length - 1),
        ],
      ),
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
