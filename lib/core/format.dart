import 'package:flutter/material.dart';

String _two(int n) => n.toString().padLeft(2, '0');

DateTime? parseServerTime(dynamic iso) => iso is String ? DateTime.parse(iso).toLocal() : null;

String fmtTime(dynamic iso) {
  final dt = parseServerTime(iso);
  return dt == null ? '--:--' : '${_two(dt.hour)}:${_two(dt.minute)}';
}

String fmtDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String fmtHours(num? hours) {
  final minutes = ((hours ?? 0) * 60).round();
  return '${minutes ~/ 60}h ${_two(minutes % 60)}m';
}

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const _currencySymbols = {'INR': '₹', 'USD': '\$', 'EUR': '€'};

String fmtMoney(num? amount, [String? currency = 'INR']) {
  final value = (amount ?? 0).abs().toStringAsFixed(2).split('.');
  final grouped = value[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final symbol = _currencySymbols[currency] ?? '${currency ?? ''} ';
  return '${(amount ?? 0) < 0 ? '-' : ''}$symbol$grouped.${value[1]}';
}

/// Odoo sends `false` for an empty text field, so never cast such a value to
/// String: read it through here.
String? asText(dynamic value) {
  if (value == null || value == false) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String fmtQty(num qty) => qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toStringAsFixed(2);

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// The one way the app tells somebody something is wrong or missing: a dialog
/// that has to be dismissed, so it is read. [message] is a text or a list of
/// things to put right.
Future<void> showProblem(BuildContext context, Object message, {String title = 'Please check'}) {
  final items = message is List
      ? message.map((e) => '$e').toList()
      : [('$message').replaceFirst(RegExp(r'^(Exception|ApiException|Bad state): '), '')];
  const red = Color(0xFFE5484D);
  return showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      contentPadding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: red.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.priority_high_rounded, color: red),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
          ]),
          const SizedBox(height: 14),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (items.length > 1)
                          const Padding(
                            padding: EdgeInsets.only(top: 6, right: 9),
                            child: Icon(Icons.circle, size: 6, color: red),
                          ),
                        Expanded(child: Text(item, style: const TextStyle(fontSize: 14.5, height: 1.35))),
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialog).pop(),
          style: FilledButton.styleFrom(
              minimumSize: const Size(96, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
