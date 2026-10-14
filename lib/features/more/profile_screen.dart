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
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final data = await Services.api.get('/api/v1/me/profile-details') as Map<String, dynamic>;
      if (mounted) setState(() => _info = data);
    } catch (_) {
      // Without it the page shows what the app already knows.
    }
  }

  List<Map<String, dynamic>> _list(String key) =>
      ((_info?[key] as List?) ?? []).cast<Map<String, dynamic>>();

  Map<String, dynamic> _map(String key) => (_info?[key] as Map?)?.cast<String, dynamic>() ?? const {};

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

  Widget _hero(Profile profile) {
    final colour = _map('colour');
    final start = _hex(colour['start'] as String?, AppColors.primary);
    final end = _hex(colour['end'] as String?, const Color(0xFF6D5DF6));
    final active = '${_info?['status'] ?? 'Active'}' == 'Active';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [start, end]),
        borderRadius: BorderRadius.circular(22),
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
                      child: Text(profile.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 8),
                    _badge(Icons.circle, active ? 'Active' : 'Inactive',
                        tint: active ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5)),
                  ],
                ),
                const SizedBox(height: 2),
                if ((_info?['designation'] ?? profile.designation) != null)
                  Text('${_info?['designation'] ?? profile.designation}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(IconData icon, String text, {Color? tint}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: tint ?? Colors.white),
            const SizedBox(width: 5),
            Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  /// Team, Territory and Beats: each is a button that opens its full list.
  Widget _listButtons() {
    final teams = _list('teams');
    final primary = ((_map('territories')['primary'] as List?) ?? []).cast<Map<String, dynamic>>();
    final secondary = ((_map('territories')['secondary'] as List?) ?? []).cast<Map<String, dynamic>>();
    final outside = ((_map('territories')['outside'] as List?) ?? []).cast<Map<String, dynamic>>();
    final beats = _list('beats');
    final profile = Services.auth.profile!;
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
        cell(Icons.groups_2_rounded, 'Team', count(teams.length, 'team', 'teams'), AppColors.primary,
            () => _openList('My Teams', Icons.groups_2_rounded, [
                  for (final t in teams)
                    (t['name'] as String, 'Lead: ${t['lead'] ?? '-'} \u00B7 ${t['members']} members', null),
                ])),
        const SizedBox(width: 10),
        cell(Icons.place_rounded, 'Territory',
            count(primary.length + secondary.length + outside.length, 'territory', 'territories'), AppColors.success,
            () => _openList('My Territories', Icons.place_rounded, [
                  for (final t in primary) (t['name'] as String, '${t['region'] ?? ''}', 'Primary'),
                  for (final t in secondary) (t['name'] as String, '${t['region'] ?? ''}', 'Secondary'),
                  for (final t in outside) (t['name'] as String, '${t['region'] ?? ''}', 'Outside'),
                ])),
        const SizedBox(width: 10),
        cell(Icons.route_rounded, profile.routeLabel == 'Beat' ? 'Beats' : '${profile.routeLabel}s',
            count(beats.length, 'beat', 'beats'), AppColors.warning,
            () => _openList('My Beats', Icons.route_rounded, [
                  for (final b in beats)
                    (
                      b['name'] as String,
                      '${b['outlets']} outlets${b['city'] != null ? ' \u00B7 ${b['city']}' : ''}',
                      b['state'] == 'pending' ? 'Pending approval' : 'Approved',
                    ),
                ])),
      ],
    );
  }

  /// A simple list page: a title, then rows with a name, a line under it and a small status.
  void _openList(String title, IconData icon, List<(String, String, String?)> rows) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: rows.isEmpty
            ? const Center(child: Text('Nothing here yet.', style: TextStyle(color: AppColors.muted)))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final row in rows)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                            child: Icon(icon, color: AppColors.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(row.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                if (row.$2.isNotEmpty)
                                  Text(row.$2, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                              ],
                            ),
                          ),
                          if (row.$3 != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (row.$3 == 'Pending approval' || row.$3 == 'Outside'
                                        ? AppColors.warning
                                        : AppColors.success)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(row.$3!,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: row.$3 == 'Pending approval' || row.$3 == 'Outside'
                                          ? AppColors.warning
                                          : AppColors.success)),
                            ),
                        ],
                      ),
                    ),
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

  Widget _details(Profile profile) {
    final d = _map('details');
    final rows = <(IconData, String, String?)>[
      (Icons.supervisor_account_rounded, 'Reports to', (d['reports_to'] as String?) ?? profile.manager),
      (Icons.apartment_rounded, 'Department', d['department'] as String?),
      (Icons.badge_rounded, 'Employee ID', (d['employee_id'] as String?) ?? profile.code),
    ].where((row) => (row.$3 ?? '').isNotEmpty).toList();
    return _section(
      icon: Icons.person_rounded,
      title: 'Employee Details',
      children: [
        for (final (i, row) in rows.indexed)
          _row(row.$1, row.$2, row.$3!, last: i == rows.length - 1),
      ],
    );
  }

  /// The company the person works for.
  Widget _company() {
    final c = _map('company');
    final rows = <(IconData, String, String?)>[
      (Icons.business_rounded, 'Company', c['name'] as String?),
      (Icons.receipt_long_rounded, 'GSTIN', c['gstin'] as String?),
      (Icons.language_rounded, 'Website', c['website'] as String?),
      (Icons.camera_alt_rounded, 'Instagram', c['instagram'] as String?),
    ].where((row) => (row.$3 ?? '').isNotEmpty).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _section(
        icon: Icons.business_center_rounded,
        title: 'Company Details',
        children: [
          for (final (i, row) in rows.indexed)
            _row(row.$1, row.$2, row.$3!, last: i == rows.length - 1),
        ],
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

  Widget _tile(IconData icon, String label, String value, String hint, Color tint) => Container(
        padding: const EdgeInsets.all(11),
        decoration:
            BoxDecoration(color: tint.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(15)),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(icon, size: 19, color: Colors.white),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  Text(value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  if (hint.isNotEmpty)
                    Text(hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ),
          ],
        ),
      );

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
