import 'package:flutter/material.dart';

import '../core/services.dart';
import '../core/theme.dart';
import '../features/more/sync_screen.dart';

/// "Tracking on · All synced" line; tap it to see what is waiting.
class SyncStatusBar extends StatelessWidget {
  const SyncStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        Services.tracker.active,
        Services.tracker.pending,
        Services.outbox.pending,
        Services.outbox.failed,
        Services.api.online,
      ]),
      builder: (context, _) {
        final active = Services.tracker.active.value;
        final actions = Services.outbox.pending.value;
        final failed = Services.outbox.failed.value;
        final pings = Services.tracker.pending.value;
        final online = Services.api.online.value;
        final parts = <String>[
          active ? 'Tracking on' : 'Tracking off',
          if (!online) 'Offline',
          if (failed > 0) '$failed need attention',
          if (actions > 0) '$actions action${actions == 1 ? '' : 's'} waiting',
          if (pings > 0) '$pings locations waiting',
          if (failed == 0 && actions == 0 && pings == 0) 'All synced',
        ];
        return InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncScreen())),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  failed > 0
                      ? Icons.error_outline_rounded
                      : !online
                          ? Icons.cloud_off_rounded
                          : active
                              ? Icons.gps_fixed_rounded
                              : Icons.gps_off_rounded,
                  size: 16,
                  color: failed > 0
                      ? AixoloColors.danger
                      : !online
                          ? AixoloColors.warning
                          : active
                              ? AixoloColors.success
                              : AixoloColors.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(parts.join(' · '), style: const TextStyle(fontSize: 12, color: AixoloColors.muted)),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18, color: AixoloColors.muted),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A thin strip across the top of the app while there is no network.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Services.api.online, Services.outbox.pending, Services.outbox.failed]),
      builder: (context, _) {
        final online = Services.api.online.value;
        final waiting = Services.outbox.pending.value;
        final failed = Services.outbox.failed.value;
        if (online && failed == 0) return const SizedBox.shrink();
        final colour = failed > 0 ? AixoloColors.danger : AixoloColors.warning;
        final text = failed > 0
            ? '$failed action${failed == 1 ? '' : 's'} could not be saved · tap to review'
            : 'You are offline${waiting > 0 ? ' · $waiting waiting to sync' : ''} · work is saved on the phone';
        return Material(
          color: colour,
          child: SafeArea(
            bottom: false,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncScreen())),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  children: [
                    Icon(failed > 0 ? Icons.error_outline_rounded : Icons.cloud_off_rounded,
                        size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(text,
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
