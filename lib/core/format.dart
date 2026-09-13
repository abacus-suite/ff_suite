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
