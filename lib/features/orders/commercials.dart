import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';

/// An outlet's commercials, as the server sends them: the price category (149 / 179), the scheme off
/// every bottle and the outlet's margin. The rate is MRP - scheme - margin %, incl. GST.
///
/// The server works out the rate and sends it as each product's `price`; the app only shows how it is made.
/// Read from `commercials` on the products answer or on the outlet:
/// `{price_category: "149", scheme_per_bottle: 30, margin_percent: 20}`.
class Commercials {
  const Commercials({this.category, this.scheme, this.margin, this.mrpId, this.mrpName});

  final String? category;
  final num? scheme;
  final num? margin;
  final int? mrpId;
  final String? mrpName;

  bool get isEmpty => category == null && scheme == null && margin == null && mrpName == null;

  static Commercials? from(dynamic raw) {
    if (raw is! Map) return null;
    num? n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}');
    final mrpObj = raw['mrp'];
    final mrpId = raw['mrp_id'] is num
        ? (raw['mrp_id'] as num).toInt()
        : (mrpObj is Map && mrpObj['id'] is num ? (mrpObj['id'] as num).toInt() : null);
    final mrpName = asText(raw['mrp_name'] ?? (mrpObj is Map ? mrpObj['name'] : null));
    final c = Commercials(
      category: asText(raw['price_category']),
      scheme: n(raw['scheme_per_bottle']),
      margin: n(raw['margin_percent']),
      mrpId: mrpId,
      mrpName: mrpName,
    );
    return c.isEmpty ? null : c;
  }

  /// The first that has them: the products answer, then the outlet.
  static Commercials? of(Map? products, Map? client) => from(products?['commercials']) ?? from(client?['commercials']);
}

String _rupees(num v) => '₹${v.toStringAsFixed(2)}';

/// "MRP ₹149 · rate ₹95.20" under a product, from the server's MRP and rate.
String? mrpRateLine(Map p) {
  final mrp = p['mrp'] as num?;
  final rate = p['price'] as num?;
  if (mrp == null && rate == null) return null;
  return [if (mrp != null) 'MRP ${fmtMoney(mrp)}', if (rate != null) 'rate ${_rupees(rate)}'].join(' · ');
}

/// "Outlet commercials": price category, scheme and margin of this outlet.
class CommercialsCard extends StatelessWidget {
  const CommercialsCard({super.key, required this.commercials});

  final Commercials commercials;

  @override
  Widget build(BuildContext context) {
    final c = commercials;
    return _Box(title: 'Outlet commercials', rows: [
      if (c.mrpName != null) ('MRP Master', c.mrpName!, null)
      else if (c.category != null) ('Price category', '₹${c.category}', null),
      if (c.scheme != null) ('Scheme', '${_rupees(c.scheme!).replaceAll('.00', '')} per bottle', null),
      if (c.margin != null) ('Margin', '${fmtQty(c.margin!)}%', null),
    ]);
  }
}

/// "Rate – Alphonso Mango (AM)": MRP, less scheme, after scheme, less margin, then the rate incl. GST.
/// The rate is the server's; the lines above it show how it comes about.
class RateBreakdown extends StatelessWidget {
  const RateBreakdown(
      {super.key, required this.title, required this.mrp, required this.rate, required this.commercials, this.tax});

  final String title;
  final num mrp;
  final num rate;
  final Commercials commercials;

  /// The GST percentage that is inside the rate.
  final num? tax;

  @override
  Widget build(BuildContext context) {
    final scheme = commercials.scheme ?? 0;
    final after = mrp - scheme;
    final margin = commercials.margin;
    return _Box(title: 'Rate – $title', rows: [
      ('MRP', _rupees(mrp), null),
      if (scheme > 0) ('Less scheme', '− ${_rupees(scheme)}', AppColors.danger),
      if (scheme > 0) ('After scheme', _rupees(after), AppColors.text),
      if (margin != null && margin > 0) ('Less margin ${fmtQty(margin)}%', '− ${_rupees(after * margin / 100)}', AppColors.danger),
    ], footer: (label: tax != null && tax! > 0 ? 'Rate incl. GST ${fmtQty(tax!)}%' : 'Rate incl. GST', value: _rupees(rate)));
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.title, required this.rows, this.footer});

  final String title;

  /// Label, value, and the value's colour (null is the usual text).
  final List<(String, String, Color?)> rows;
  final ({String label, String value})? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        const SizedBox(height: 6),
        for (final (label, value, colour) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        color: colour == AppColors.text ? AppColors.text : AppColors.muted,
                        fontWeight: colour == AppColors.text ? FontWeight.w800 : FontWeight.w500)),
              ),
              Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: colour ?? AppColors.text)),
            ]),
          ),
        if (footer != null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
            ),
            child: Row(children: [
              Expanded(child: Text(footer!.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
              Text(footer!.value,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.success)),
            ]),
          ),
      ]),
    );
  }
}
