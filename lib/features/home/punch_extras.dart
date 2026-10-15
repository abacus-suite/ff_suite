import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// What the app asks for at a punch when the office turned it on: how the
/// person is travelling today, and what the odometer reads.

const vehicleChoices = <(String, String, IconData)>[
  ('two_wheeler', 'Two-wheeler', Icons.two_wheeler_rounded),
  ('four_wheeler', 'Four-wheeler', Icons.directions_car_rounded),
  ('public', 'Public transport', Icons.directions_bus_rounded),
  ('walk', 'On foot', Icons.directions_walk_rounded),
  ('other', 'Other', Icons.more_horiz_rounded),
];

/// Returns the chosen vehicle, or null when the person backs out.
Future<String?> askVehicle(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text('How are you travelling today?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Your travel allowance is worked out from this.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
            ),
            for (final (code, label, icon) in vehicleChoices)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Icon(icon, color: AppColors.primary),
                ),
                title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => Navigator.of(sheet).pop(code),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

/// Returns the reading typed in, or null when the person backs out.
Future<double?> askOdometer(BuildContext context) async {
  final controller = TextEditingController();
  return showDialog<double>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) {
      String? error;
      return StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const Text('Odometer reading'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Type the number showing on the photo you just took.',
                  style: TextStyle(fontSize: 13, color: AppColors.muted)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(
                  labelText: 'Kilometres',
                  suffixText: 'km',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialog).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(controller.text.trim());
                if (value == null || value <= 0) {
                  setState(() => error = 'Enter the number on the odometer.');
                  return;
                }
                Navigator.of(dialog).pop(value);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    },
  );
}
