import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/sync_status.dart';
import '../auth/login_screen.dart';

const _scopeLabels = {
  'own': 'Own records',
  'hierarchy': 'Team reporting to me',
  'team': 'My field team',
  'all': 'All employees',
};

/// Who is logged in, and the way out. Everything else lives in More.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Tracking stops and unsent locations are uploaded first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirm != true) return;
    await Services.tracker.stop();
    await Services.auth.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final profile = Services.auth.profile!;
    final work = <(IconData, String, String?)>[
      (Icons.badge_rounded, 'Employee code', profile.code),
      (Icons.work_outline_rounded, 'Designation', profile.designation),
      (Icons.groups_rounded, 'Team', profile.team),
      (Icons.supervisor_account_rounded, 'Reports to', profile.manager),
      (Icons.schedule_rounded, 'Shift', profile.shiftName),
      (Icons.route_rounded, '${profile.routeLabel}s', profile.routes.map((r) => r.name).join(', ')),
      (Icons.visibility_rounded, 'Data access', _scopeLabels[profile.scope]),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AixoloColors.brandGradient,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: Colors.white,
                  child: Text(profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: AixoloColors.primary, fontWeight: FontWeight.w800, fontSize: 28)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(profile.name,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text([profile.designation, profile.code].whereType<String>().join(' · '),
                          style: const TextStyle(color: Color(0xE6FFFFFF))),
                      if (profile.isManager) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x33FFFFFF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Manager',
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                for (final item in work)
                  if ((item.$3 ?? '').isNotEmpty)
                    ListTile(
                      leading: Icon(item.$1, color: AixoloColors.primary),
                      title: Text(item.$2, style: const TextStyle(color: AixoloColors.muted, fontSize: 12)),
                      subtitle: Text(item.$3!, style: const TextStyle(color: AixoloColors.text, fontSize: 15)),
                    ),
              ],
            ),
          ),
          const Card(
            child: Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: SyncStatusBar()),
          ),
          Card(
            child: FutureBuilder(
              future: Future.wait([PackageInfo.fromPlatform(), Services.api.url('')]),
              builder: (context, snapshot) {
                final info = snapshot.data?[0] as PackageInfo?;
                final server = snapshot.data?[1] as String?;
                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.phone_android_rounded, color: AixoloColors.primary),
                      title: const Text('App version', style: TextStyle(color: AixoloColors.muted, fontSize: 12)),
                      subtitle: Text(info == null ? '…' : '${info.version} (${info.buildNumber})',
                          style: const TextStyle(color: AixoloColors.text, fontSize: 15)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.dns_rounded, color: AixoloColors.primary),
                      title: const Text('Server', style: TextStyle(color: AixoloColors.muted, fontSize: 12)),
                      subtitle: Text(server ?? '…', style: const TextStyle(color: AixoloColors.text, fontSize: 15)),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          GradientButton(
            label: 'Log out',
            icon: Icons.logout_rounded,
            gradient: AixoloColors.dangerGradient,
            onPressed: () => _logout(context),
          ),
        ],
      ),
    );
  }
}
