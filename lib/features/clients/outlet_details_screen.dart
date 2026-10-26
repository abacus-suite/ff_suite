import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../orders/commercials.dart';

/// Outlet details, from the "i" on the outlet screen: everything known about the outlet, view only.
/// Changes are made by the office, so there is no edit here.
class OutletDetailsScreen extends StatelessWidget {
  const OutletDetailsScreen({super.key, required this.client});

  final Map<String, dynamic> client;

  /// A name from a field the server may send as text, as `{name}` or as Odoo's `[id, name]`.
  static String? _name(dynamic v) {
    if (v is Map) return asText(v['name']) ?? asText(v['display_name']);
    if (v is List && v.length > 1) return asText(v[1]);
    if (v == false) return null;
    return asText(v);
  }

  static String? _first(Map<String, dynamic> c, List<String> keys) {
    for (final k in keys) {
      final v = _name(c[k]);
      if (v != null) return v;
    }
    return null;
  }

  static String? _yesNo(dynamic v) => v == null ? null : (v == true || v == 1 || '$v'.toLowerCase() == 'yes' ? 'Yes' : 'No');

  String get _status {
    final c = client;
    if (c['onboarded'] == true) return 'Onboarded';
    if (c['onboard_pending'] == true) return 'Onboarding pending';
    return _first(c, ['status', 'state', 'approval_state'])?.replaceAll('_', ' ') ?? 'Not onboarded';
  }

  String? get _districtTerritory {
    final c = client;
    final district = _first(c, ['district', 'district_name']);
    final territory = _first(c, ['territory', 'territory_name']);
    final parts = [if (district != null) district, if (territory != null && territory != district) territory];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? get _poc {
    final c = client;
    final person = c['poc'] ?? c['contact_person'] ?? c['contact'];
    final name = _name(person) ?? asText(c['poc_name']) ?? asText(c['contact_name']);
    final phone = (person is Map ? asText(person['phone']) ?? asText(person['mobile']) : null) ??
        asText(c['poc_phone']) ??
        asText(c['contact_phone']);
    final parts = [if (name != null) name, if (phone != null) phone];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? get _creditDays {
    final c = client;
    final days = c['credit_days'] ?? c['credit_period'];
    if (days is num) return fmtQty(days);
    return asText(days) ?? _first(c, ['payment_term', 'property_payment_term_id']);
  }

  String? get _swiggyZomato {
    final swiggy = _yesNo(client['swiggy'] ?? client['on_swiggy']);
    final zomato = _yesNo(client['zomato'] ?? client['on_zomato']);
    if (swiggy == null && zomato == null) return null;
    return '${swiggy ?? '—'} · ${zomato ?? '—'}';
  }

  @override
  Widget build(BuildContext context) {
    final c = client;
    final comm = Commercials.from(c['commercials']) ?? Commercials.from(c);
    String? schemeMargin;
    if (comm?.scheme != null || comm?.margin != null) {
      schemeMargin = [
        comm?.scheme == null ? '—' : '₹${fmtQty(comm!.scheme!)}',
        comm?.margin == null ? '—' : '${fmtQty(comm!.margin!)}%',
      ].join(' · ');
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Outlet details', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
          Text('View only – cannot be edited here', style: TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 32), children: [
        _Section(title: 'Outlet', rows: [
          ('Status', _status),
          ('Category', _first(c, ['category', 'category_name'])),
          ('Name as per GST', _first(c, ['gst_name', 'legal_name', 'company_registry_name', 'trade_name'])),
          ('GSTIN', _first(c, ['gst', 'gstin', 'vat'])),
          ('Region', _first(c, ['region', 'region_name', 'state', 'state_id'])),
          ('District / Territory', _districtTerritory),
        ]),
        _Section(title: 'Contact & commercials', rows: [
          ('POC', _poc),
          ('MRP category', comm?.category == null ? null : '₹${comm!.category}'),
          ('Scheme · Margin', schemeMargin),
          ('Credit days', _creditDays),
          ('Distributor', _first(c, ['distributor', 'distributor_name'])),
          ('Swiggy · Zomato', _swiggyZomato),
        ]),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<(String, String?)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
        const SizedBox(height: 6),
        for (final (i, (label, value)) in rows.indexed) ...[
          if (i > 0) const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 4,
                child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 6,
                child: Text(value ?? '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: value == null ? AppColors.muted : const Color(0xFF0F172A))),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}
