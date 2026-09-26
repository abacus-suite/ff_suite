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
import '../../widgets/member_picker.dart';
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
  int? _teamCount;
  double? _targetPercent;

  @override
  void initState() {
    super.initState();
    _loadFigures();
  }

  /// The numbers across the top: how big the team is and how the month is going.
  Future<void> _loadFigures() async {
    try {
      final scope = await TeamScope.load();
      if (mounted) setState(() => _teamCount = ((scope['members'] as List?) ?? []).length);
    } catch (_) {
      // Somebody without a team simply has no number to show.
    }
    try {
      final data = await Services.api.get('/api/v1/targets') as Map<String, dynamic>;
      final mine = (data['me'] as Map?)?.cast<String, dynamic>();
      final rows = ((mine?['targets'] as List?) ?? (data['targets'] as List?) ?? [])
          .cast<Map<String, dynamic>>();
      if (rows.isNotEmpty) {
        final done = rows
            .map((row) => ((row['percent'] as num?) ?? 0).toDouble())
            .reduce((a, b) => a + b) /
            rows.length;
        if (mounted) setState(() => _targetPercent = done);
      }
    } catch (_) {}
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
          _figures(profile),
          const SizedBox(height: 12),
          _details(profile),
          const SizedBox(height: 12),
          _work(profile),
          const SizedBox(height: 12),
          _permissions(profile),
          const SizedBox(height: 12),
          const Card(
            margin: EdgeInsets.zero,
            child: Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: SyncStatusBar()),
          ),
          const SizedBox(height: 12),
          _appInfo(),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, Color(0xFF6D5DF6)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ChangeablePhoto(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(profile.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
                if (profile.designation != null)
                  Text(profile.designation!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 14)),
                if (profile.code != null)
                  Text(profile.code!, style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 13)),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    if (profile.isManager) _badge(Icons.work_rounded, 'Manager'),
                    if (profile.isAdmin) _badge(Icons.shield_rounded, 'Admin'),
                    _badge(Icons.check_circle_rounded, 'Active', tint: AppColors.success),
                  ],
                ),
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

  Widget _figures(Profile profile) {
    final cells = <(IconData, String, String, Color)>[
      if (profile.team != null)
        (Icons.apartment_rounded, profile.team!, 'Team', AppColors.primary),
      if (_teamCount != null && _teamCount! > 0)
        (Icons.groups_2_rounded, '$_teamCount', 'Team members', AppColors.success),
      if (profile.routes.isNotEmpty)
        (Icons.route_rounded, '${profile.routes.length}', '${profile.routeLabel}s', AppColors.warning),
      if (_targetPercent != null)
        (Icons.adjust_rounded, '${_targetPercent!.round()}%', 'Target', AppColors.purple),
    ];
    if (cells.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, cell) in cells.indexed) ...[
                if (i > 0) VerticalDivider(width: 1, color: AppColors.border),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(cell.$1, size: 20, color: cell.$4),
                        const SizedBox(height: 6),
                        Text(cell.$2,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                        Text(cell.$3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ),
              Flexible(
                child: Text(value,
                    textAlign: TextAlign.right,
                    maxLines: 2,
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
    final rows = <(IconData, String, String?)>[
      (Icons.badge_rounded, 'Employee code', profile.code),
      (Icons.work_outline_rounded, 'Designation', profile.designation),
      (Icons.groups_rounded, 'Team', profile.team),
      (Icons.supervisor_account_rounded, 'Reports to', profile.manager),
      if (profile.routes.isNotEmpty)
        (Icons.route_rounded, '${profile.routeLabel}s', profile.routes.map((r) => r.name).join(', ')),
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

  Widget _work(Profile profile) {
    final hours = _shiftHours;
    if (profile.shiftName == null && hours == null) return const SizedBox.shrink();
    return _section(
      icon: Icons.schedule_rounded,
      title: 'Work Information',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: _tile(Icons.access_time_filled_rounded, 'Shift', profile.shiftName ?? 'Not set',
                    hours ?? '', AppColors.purple),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _tile(Icons.place_rounded, 'Work type', 'Field work', '', AppColors.success),
              ),
            ],
          ),
        ),
      ],
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
                      maxLines: 1,
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
      Services.refresh.value++;
      if (mounted) showSnack(context, 'Photo updated');
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
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
