import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../orders/commercials.dart';
import '../tasks/onboard_screen.dart' show schemeLabel;

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

  /// What was taken at onboarding (the server sends it with the contact), as a map; empty before onboarding.
  Map<String, dynamic> get _ob => (client['onboarding'] as Map?)?.cast<String, dynamic>() ?? const {};

  static const _statusNames = {
    'new_lead': 'New Lead',
    'onboard_pending': 'Confirmed – details pending',
    'onboarded': 'Onboarded',
    'stopped': 'Stopped',
    'not_interested': 'Not interested',
  };

  String? get _onboardedOn {
    final day = DateTime.tryParse('${_ob['onboarded_date'] ?? ''}');
    return day == null ? null : '${day.day} ${monthNames[day.month - 1].substring(0, 3)} ${day.year}';
  }

  /// A name from one of the onboarding options ({code, name}), or null.
  static String? _option(dynamic v) => v is Map ? asText(v['name']) : null;

  @override
  Widget build(BuildContext context) {
    final c = client;
    final ob = _ob;
    final comm = Commercials.from(c['commercials']) ?? Commercials.from(c);
    // Scheme is read as a percentage; the margin too.
    final scheme = _option(ob['scheme']) != null ? schemeLabel(_option(ob['scheme'])) : (comm?.scheme == null ? null : '${fmtQty(comm!.scheme!)}%');
    final margin = ob['margin'] is num && (ob['margin'] as num) != 0
        ? '${fmtQty(ob['margin'] as num)}%'
        : (comm?.margin == null ? null : '${fmtQty(comm!.margin!)}%');
    String? schemeMargin;
    if (scheme != null || margin != null) schemeMargin = [scheme ?? '—', margin ?? '—'].join(' · ');
    final mrp = _option(ob['mrp']);
    final mrpText = mrp != null ? (RegExp(r'^\d+(\.\d+)?$').hasMatch(mrp.trim()) ? '₹${mrp.trim()}' : mrp) : (comm?.category == null ? null : '₹${comm!.category}');
    final poc = [asText(ob['poc_name']), asText(ob['poc_phone'])].whereType<String>();
    final yes = (dynamic v) => v == true ? 'Yes' : 'No';
    final apps = ob.containsKey('swiggy') ? '${yes(ob['swiggy'])} · ${yes(ob['zomato'])}' : _swiggyZomato;
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
          ('Status', _statusNames['${ob['status']}'] ?? _status),
          ('Category', _option(ob['outlet_category']) ?? _first(c, ['category', 'category_name'])),
          ('Name as per GST', asText(ob['gst_name']) ?? _first(c, ['gst_name', 'legal_name', 'company_registry_name', 'trade_name'])),
          ('GSTIN', ob['has_gst'] == false ? 'No GST' : _first(c, ['gst', 'gstin', 'vat'])),
          ('Region', _first(c, ['region', 'region_name'])),
          ('District / Territory', _districtTerritory),
          if (_onboardedOn != null) ('Onboarded on', _onboardedOn),
        ]),
        _Section(title: 'Contact & commercials', rows: [
          ('POC', poc.isEmpty ? _poc : poc.join(' · ')),
          ('MRP category', mrpText),
          ('Scheme · Margin', schemeMargin),
          ('Credit days', ob['credit_days'] is num ? fmtQty(ob['credit_days'] as num) : _creditDays),
          ('Distributor', _option(ob['distributor']) ?? _first(c, ['distributor', 'distributor_name'])),
          ('Swiggy · Zomato', apps),
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
