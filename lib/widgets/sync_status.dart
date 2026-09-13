import 'package:flutter/material.dart';

import '../core/services.dart';
import '../core/theme.dart';

/// "Tracking on · All synced" line with a Sync now button.
class SyncStatusBar extends StatelessWidget {
  const SyncStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Services.tracker.active,
      builder: (context, active, _) => ValueListenableBuilder<int>(
        valueListenable: Services.tracker.pending,
        builder: (context, pending, _) => Row(
          children: [
            Icon(active ? Icons.gps_fixed_rounded : Icons.gps_off_rounded, size: 16,
                color: active ? AixoloColors.success : AixoloColors.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${active ? 'Tracking on' : 'Tracking off'} · ${pending == 0 ? 'All synced' : '$pending waiting to upload'}',
                style: const TextStyle(fontSize: 12, color: AixoloColors.muted),
              ),
            ),
            if (pending > 0) TextButton(onPressed: Services.tracker.flush, child: const Text('Sync now')),
          ],
        ),
      ),
    );
  }
}
