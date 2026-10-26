import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// What a call is for, and what that means has to be done while they are there.
///
/// Asked on the way in rather than on the way out: a chiller update that is
/// only named at the end is a stock count nobody took, and standing outside
/// the shop again is too late to take it.
class VisitPurpose {
  const VisitPurpose(this.code, this.name, this.hint, this.icon, this.tasks);

  final String code;
  final String name;
  final String hint;
  final IconData icon;

  /// What must be done before this visit can be closed.
  final List<String> tasks;

  bool get needsNote => tasks.contains('note');

  bool get needsStock => tasks.contains('stock');

  bool get needsPhoto => tasks.contains('photo');
}

const visitPurposes = <VisitPurpose>[
  VisitPurpose('client_visit', 'Client Visit', 'Write it up and photograph it',
      Icons.handshake_rounded, ['note', 'photo']),
  VisitPurpose('chiller_update', 'Weekly Chiller Update', 'Count the stock, then photograph it',
      Icons.kitchen_rounded, ['stock', 'photo']),
  VisitPurpose('other', 'Other', 'Nothing else needed', Icons.more_horiz_rounded, []),
];

VisitPurpose? purposeOf(String? code) {
  for (final purpose in visitPurposes) {
    if (purpose.code == code) return purpose;
  }
  return null;
}

/// Asks what this visit is for. Returns the code, or null if they backed out.
Future<String?> askVisitPurpose(BuildContext context, String clientName, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What is this visit for?',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 2),
            Text(clientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 14),
            for (final purpose in visitPurposes)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Material(
                  color: current == purpose.code
                      ? AppColors.primary.withValues(alpha: 0.10)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.pop(sheet, purpose.code),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: current == purpose.code ? AppColors.primary : Colors.transparent,
                            width: 1.4),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                                color: Colors.white, borderRadius: BorderRadius.circular(13)),
                            child: Icon(purpose.icon, size: 20, color: AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(purpose.name,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                Text(purpose.hint,
                                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            const Text('Your location is matched with the customer before the visit starts.',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ],
        ),
      ),
    ),
  );
}
