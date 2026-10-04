import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/local_state.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../clients/clients_screen.dart';
import '../collections/collect_payment_screen.dart';
import 'task_widgets.dart';

/// Whether a task screen is on show, so a visit left open is not reopened over itself.
bool taskScreenOpen = false;

/// One screen of a task.
class _Step {
  _Step(this.number, this.title, this.body, this.check);

  /// Its number in the full sequence, which stays the same when a step is skipped.
  final int number;
  final String title;
  final Widget Function() body;

  /// What is still wrong with this step, or null when it is complete.
  final String? Function() check;
}

/// The six sales tasks, each a fixed sequence of mandatory screens.
///
/// Every answer is kept on this screen and sent once, at the very end, so a
/// task can be finished on a phone without a signal and still arrive whole.
/// Next stays shut until the screen in front is complete.
class TaskFlowScreen extends StatefulWidget {
  const TaskFlowScreen({super.key, required this.code, required this.config, this.client, this.visit});

  final String code;
  final Map<String, dynamic> config;
  final Map<String, dynamic>? client;
  final Map<String, dynamic>? visit;

  @override
  State<TaskFlowScreen> createState() => _TaskFlowScreenState();
}

class _TaskFlowScreenState extends State<TaskFlowScreen> {
  final String _uuid = const Uuid().v4();
  final Map<String, dynamic> _a = {};
  final Map<String, List<Uint8List>> _photos = {};
  final Map<String, TextEditingController> _text = {};
  final Map<String, Map<int, double>> _qty = {};
  final Set<int> _available = {};
  Map<String, dynamic>? _client;
  Map<String, dynamic>? _ledger;
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _cities = [];
  int _index = 0;
  bool _busy = false;

  Map<String, dynamic> get _lists => (widget.config['lists'] as Map).cast<String, dynamic>();

  List<Map<String, dynamic>> _list(String key) =>
      ((_lists[key] as List?) ?? []).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> get _flavours =>
      ((widget.config['flavours'] as List?) ?? []).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> get _materials =>
      ((widget.config['materials'] as List?) ?? []).cast<Map<String, dynamic>>();

  String get _name => widget.code == 'client_visit'
      ? 'Client Visit'
      : widget.code == 'new_lead'
          ? 'New Lead'
          : widget.code == 'lead_follow_up'
              ? 'New Lead Follow Up'
              : widget.code == 'adhoc'
                  ? 'Adhoc Task'
                  : widget.code == 'sample_collection'
                      ? 'Sample Collection'
                      : 'Marketing Material Supply';

  TextEditingController _t(String key) => _text.putIfAbsent(key, TextEditingController.new);

  String _s(String key) => _t(key).text.trim();

  Map<int, double> _q(String key) => _qty.putIfAbsent(key, () => {});

  List<Uint8List> _p(String key) => _photos.putIfAbsent(key, () => []);

  @override
  void initState() {
    super.initState();
    taskScreenOpen = true;
    _client = widget.client;
    if (widget.code == 'sample_collection' && widget.client != null) {
      // Checked in at a contact, so that contact is where the samples come from:
      // a distributor if it is one, an outlet if it is not. Nothing to ask.
      final distributor = widget.client!['category_type'] == 'distributor';
      _a['source'] = distributor ? 'distributor' : 'outlet';
      if (distributor) {
        _a['distributor'] = widget.client;
      } else {
        _a['source_outlet'] = widget.client;
      }
    }
    if (widget.code == 'client_visit') _loadLedger();
    if (widget.code == 'new_lead') _loadLeadLists();
  }

  @override
  void dispose() {
    taskScreenOpen = false;
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------------ loading
  Future<void> _loadLedger() async {
    if (_client == null) return;
    try {
      final data = await Services.api.get('/api/v1/receivables',
          query: {'partner_id': _client!['id'], 'filter': 'open'}) as Map<String, dynamic>;
      if (mounted) setState(() => _ledger = data);
    } catch (_) {
      // Without it the step still shows, and asks for the ledger to be sent.
    }
  }

  Future<void> _loadLeadLists() async {
    try {
      final routes = (await Services.api.get('/api/v1/my-routes') as List).cast<Map<String, dynamic>>();
      final cities = (await Services.api.get('/api/v1/districts') as List).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _routes = routes;
          _cities = cities;
        });
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------------ the steps
  List<_Step> _steps() {
    switch (widget.code) {
      case 'client_visit':
        final open = _a['open'] as bool?;
        final first = _Step(1, 'Outlet Photos', _stepOutletPhotos, _checkOutletPhotos);
        final payment = _Step(5, 'Payment & Ledger', _stepPayment, _checkPayment);
        final outcome = _Step(7, 'How Did It Go?', _stepVisitOutcome, _checkVisitOutcome);
        if (open == false) return [first, payment, outcome];
        return [
          first,
          _Step(2, 'Closing Stock', _stepStock, _checkStock),
          _Step(3, 'New Demand', _stepDemand, _checkDemand),
          _Step(4, 'Marketing Material', _stepMaterialCheck, () => null),
          payment,
          _Step(6, 'Damage / Expiry', _stepDamage, _checkDamage),
          outcome,
        ];
      case 'new_lead':
        return [_Step(1, 'Contact Creation', _stepContact, _checkContact), ..._meetingSteps(2)];
      case 'lead_follow_up':
        return _meetingSteps(1);
      case 'adhoc':
        return [_Step(1, 'Photo & Description', _stepAdhoc, _checkAdhoc)];
      case 'sample_collection':
        return [_Step(1, 'Sample Details', _stepSample, _checkSample)];
      default:
        return [_Step(1, 'Supply Details', _stepSupply, _checkSupply)];
    }
  }

  /// Steps 2 to 7 of a lead, shared by the first visit and every follow-up.
  List<_Step> _meetingSteps(int from) => [
        _Step(from, 'Person Met', _stepPerson, _checkPerson),
        _Step(from + 1, 'Samples Given', _stepSamples, _checkSamples),
        _Step(from + 2, 'Margin Discussed', _stepMargin, () => _s('margin').isEmpty ? 'Describe the margin discussed.' : null),
        _Step(from + 3, 'Meeting Update', _stepUpdate, () => _s('update').isEmpty ? 'Describe the meeting.' : null),
        _Step(from + 4, 'Outcome', _stepLeadOutcome, _checkLeadOutcome),
        _Step(from + 5, 'How Did It Go?', _stepMeetingResult, _checkMeetingResult),
      ];

  int get _total => widget.code == 'client_visit'
      ? 7
      : widget.code == 'new_lead'
          ? 7
          : widget.code == 'lead_follow_up'
              ? 6
              : 1;

  // ------------------------------------------------------------------ client visit
  Widget _stepOutletPhotos() {
    final open = _a['open'] as bool?;
    return Column(
      children: [
        StepCard(
          title: 'Is the outlet open? *',
          child: YesNo(value: open, onChanged: (v) => setState(() => _a['open'] = v)),
        ),
        if (open != null)
          StepCard(
            title: 'Photos *',
            note: open
                ? 'Open: a photo of the stock and a photo of the outlet.'
                : 'Closed: only the outlet photo. Stock, demand, material and damage are marked NA.',
            child: Column(
              children: [
                if (open) PhotoSlot(label: 'Stock', photos: _p('stock'), onChanged: _refresh, max: 2),
                if (open) const SizedBox(height: 10),
                PhotoSlot(label: 'Outlet', photos: _p('outlet'), onChanged: _refresh, max: 2),
              ],
            ),
          ),
      ],
    );
  }

  String? _checkOutletPhotos() {
    final open = _a['open'] as bool?;
    if (open == null) return 'Say whether the outlet is open.';
    if (open && _p('stock').isEmpty) return 'Take the photo of the stock.';
    if (_p('outlet').isEmpty) return 'Take the photo of the outlet.';
    return null;
  }

  Widget _stepStock() => StepCard(
        title: 'Closing stock *',
        note: 'What is lying at the outlet right now, flavour by flavour. Every box must be filled.',
        child: QtyGrid(products: _flavours, values: _q('stock'), onChanged: _refresh, requireAll: true),
      );

  String? _checkStock() {
    final missing = _flavours.where((p) => !_q('stock').containsKey(p['id'])).length;
    return missing > 0 ? 'Fill every flavour, with 0 where there is none.' : null;
  }

  Widget _stepDemand() {
    final wanted = _a['demand'] as bool?;
    final anyFree = _q('free').values.any((v) => v > 0);
    return Column(
      children: [
        StepCard(
          title: 'New demand (PO)? *',
          child: YesNo(value: wanted, onChanged: (v) => setState(() => _a['demand'] = v)),
        ),
        if (wanted == false)
          StepCard(
            title: 'Why no demand? *',
            child: TextAnswer(controller: _t('demand_reason'), hint: 'Type the reason', onChanged: _refresh),
          ),
        if (wanted == true) ...[
          StepCard(
            title: 'Order quantity',
            note: 'Raised to the distributor mapped to this outlet.',
            child: QtyGrid(products: _flavours, values: _q('order'), onChanged: _refresh),
          ),
          StepCard(
            title: 'Free quantity',
            note: 'Kept apart from the order. It can be the only entry.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                QtyGrid(products: _flavours, values: _q('free'), onChanged: _refresh),
                if (anyFree) ...[
                  const SizedBox(height: 10),
                  const Text('Free reason *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const SizedBox(height: 8),
                  Choice(
                    options: _list('free_reasons'),
                    value: _a['free_reason'] as String?,
                    onChanged: (v) => setState(() => _a['free_reason'] = v),
                  ),
                  if (_a['free_reason'] == 'other') ...[
                    const SizedBox(height: 10),
                    TextAnswer(
                        controller: _t('free_note'),
                        hint: 'Describe the free reason',
                        lines: 2,
                        onChanged: _refresh),
                  ],
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  String? _checkDemand() {
    final wanted = _a['demand'] as bool?;
    if (wanted == null) return 'Say whether a demand was taken.';
    if (!wanted) return _s('demand_reason').isEmpty ? 'Say why no demand was taken.' : null;
    final order = _q('order').values.any((v) => v > 0);
    final free = _q('free').values.any((v) => v > 0);
    if (!order && !free) return 'Enter the order quantity, or the free quantity.';
    if (free && _a['free_reason'] == null) return 'Say why the quantity is free.';
    if (free && _a['free_reason'] == 'other' && _s('free_note').isEmpty) return 'Describe the free reason.';
    return null;
  }

  Widget _stepMaterialCheck() => StepCard(
        title: 'Marketing material',
        note: 'Tick what the outlet has. Quantity needed is what it asks for, whether or not it has some.',
        child: _MaterialRows(
          materials: _materials,
          available: _available,
          needed: _q('needed'),
          onChanged: _refresh,
        ),
      );

  Widget _stepPayment() {
    final outstanding = ((_ledger?['total'] as num?) ?? 0).toDouble();
    final overdue = ((_ledger?['overdue'] as num?) ?? 0).toDouble();
    final count = ((_ledger?['count'] as num?) ?? 0).toInt();
    final currency = _ledger?['currency'] as String?;
    return Column(
      children: [
        StepCard(
          title: 'Receivables',
          note: 'Tap a figure to see the invoices behind it.',
          child: Row(
            children: [
              _tile('Outstanding', fmtMoney(outstanding, currency), AppColors.primary, () => _openInvoices(false)),
              const SizedBox(width: 8),
              _tile('Overdue', fmtMoney(overdue, currency), AppColors.danger, () => _openInvoices(true)),
              const SizedBox(width: 8),
              _tile('Invoices', '$count', AppColors.sky, () => _openInvoices(false)),
            ],
          ),
        ),
        StepCard(
          title: 'Ledger',
          note: outstanding > 0
              ? 'There is an amount outstanding, so the ledger must be sent to the outlet.'
              : 'Nothing outstanding. Sending the ledger is optional.',
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sendLedger,
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                  icon: Icon(_a['ledger'] == true ? Icons.check_circle_rounded : Icons.send_rounded, size: 18),
                  label: Text(_a['ledger'] == true ? 'Ledger sent' : 'Send ledger on WhatsApp'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _collect,
                  icon: const Icon(Icons.payments_rounded, size: 18),
                  label: const Text('Collect payment (optional)'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(String label, String value, Color tint, VoidCallback tap) => Expanded(
        child: Material(
          color: tint.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: tap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
              child: Column(
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: tint)),
                  const SizedBox(height: 2),
                  Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                ],
              ),
            ),
          ),
        ),
      );

  void _openInvoices(bool overdueOnly) {
    final rows = ((_ledger?['invoices'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .where((i) => !overdueOnly || ((i['days_overdue'] as num?) ?? 0) > 0)
        .toList();
    final currency = _ledger?['currency'] as String?;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(overdueOnly ? 'Overdue invoices' : 'Open invoices',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 8),
            if (rows.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Nothing here.')),
            for (final i in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${i['number']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    'Due ${i['due_date'] ?? ''}${((i['days_overdue'] as num?) ?? 0) > 0 ? ' · ${i['days_overdue']} days late' : ''}'),
                trailing: Text(fmtMoney(i['residual'] as num?, currency),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
          ],
        ),
      ),
    );
  }

  /// The ledger goes to the outlet's own contact on WhatsApp.
  Future<void> _sendLedger() async {
    final client = _client;
    if (client == null) return;
    final currency = _ledger?['currency'] as String?;
    final rows = ((_ledger?['invoices'] as List?) ?? []).cast<Map<String, dynamic>>();
    final text = StringBuffer('Statement for ${client['name']}\n');
    for (final i in rows) {
      text.writeln('${i['number']}  due ${i['due_date'] ?? '-'}  ${fmtMoney(i['residual'] as num?, currency)}');
    }
    text.writeln('Total outstanding: ${fmtMoney(((_ledger?['total'] as num?) ?? 0), currency)}');
    final phone = '${client['phone'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
    try {
      if (phone.length >= 10) {
        final number = phone.length == 10 ? '91$phone' : phone;
        final opened = await launchUrl(
            Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text.toString())}'),
            mode: LaunchMode.externalApplication);
        if (!opened) throw Exception('WhatsApp did not open.');
      } else {
        // No number on the outlet: the share sheet lets them pick the person.
        await SharePlus.instance.share(ShareParams(text: text.toString()));
      }
      if (mounted) setState(() => _a['ledger'] = true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  Future<void> _collect() async {
    if (_client == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CollectPaymentScreen(client: _client!, visitId: widget.visit?['id'] as int?),
    ));
    await _loadLedger();
  }

  String? _checkPayment() {
    final outstanding = ((_ledger?['total'] as num?) ?? 0).toDouble();
    if (outstanding > 0 && _a['ledger'] != true) return 'Send the ledger before going on.';
    return null;
  }

  Widget _stepDamage() {
    final any = _a['damage'] as bool?;
    return Column(
      children: [
        StepCard(
          title: 'Any damaged / expired bottles? *',
          child: YesNo(value: any, onChanged: (v) => setState(() => _a['damage'] = v)),
        ),
        if (any == true) ...[
          StepCard(
            title: 'Credit note quantity *',
            note: 'Raises a credit note demand. It is approved later, so nothing here blocks the upload.',
            child: QtyGrid(products: _flavours, values: _q('credit'), onChanged: _refresh),
          ),
          StepCard(
            title: 'Reason *',
            child: Choice(
              options: _list('damage_reasons'),
              value: _a['damage_reason'] as String?,
              onChanged: (v) => setState(() => _a['damage_reason'] = v),
            ),
          ),
          StepCard(
            child: PhotoSlot(label: 'Photo of the bottles', photos: _p('damage'), onChanged: _refresh, max: 2),
          ),
        ],
      ],
    );
  }

  String? _checkDamage() {
    final any = _a['damage'] as bool?;
    if (any == null) return 'Say whether any bottles were damaged or expired.';
    if (!any) return null;
    if (!_q('credit').values.any((v) => v > 0)) return 'Enter the quantity of damaged or expired bottles.';
    if (_a['damage_reason'] == null) return 'Say whether they were expired or damaged.';
    if (_p('damage').isEmpty) return 'Take the photo of the bottles.';
    return null;
  }

  Widget _stepVisitOutcome() {
    final closed = _a['open'] == false;
    final outcome = closed ? 'closed' : _a['outcome'] as String?;
    return Column(
      children: [
        StepCard(
          title: 'How did it go? *',
          note: closed ? 'The outlet was closed, so this is set for you.' : null,
          child: IgnorePointer(
            ignoring: closed,
            child: Choice(
              options: const [
                {'code': 'successful', 'name': 'Successful'},
                {'code': 'closed', 'name': 'Outlet Closed'},
                {'code': 'others', 'name': 'Others'},
              ],
              value: outcome,
              onChanged: (v) => setState(() => _a['outcome'] = v),
            ),
          ),
        ),
        if (outcome == 'others')
          StepCard(
            title: 'Description *',
            child: TextAnswer(controller: _t('outcome_note'), hint: 'Type here', onChanged: _refresh),
          ),
      ],
    );
  }

  String? _checkVisitOutcome() {
    if (_a['open'] == false) return null;
    final outcome = _a['outcome'] as String?;
    if (outcome == null || outcome == 'closed') return 'Say how the visit went.';
    if (outcome == 'others' && _s('outcome_note').isEmpty) return 'Describe how the visit went.';
    return null;
  }

  // ------------------------------------------------------------------ new lead
  Widget _stepContact() {
    final category = _a['category'] as String?;
    return Column(
      children: [
        StepCard(
          title: 'Outlet',
          child: Column(
            children: [
              TextField(
                controller: _t('name'),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => _refresh(),
                decoration: const InputDecoration(labelText: 'Name of outlet *', isDense: true),
              ),
              const SizedBox(height: 10),
              _autoField('Outlet status', 'New Lead'),
              _autoField('Geo location', 'Captured when you submit'),
              _autoField('Team', '${Services.auth.profile?.name ?? ''}'),
            ],
          ),
        ),
        StepCard(
          title: 'Outlet category *',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Choice(
                options: _list('outlet_categories'),
                value: category,
                onChanged: (v) => setState(() => _a['category'] = v),
              ),
              if (category == 'others') ...[
                const SizedBox(height: 10),
                TextAnswer(
                    controller: _t('category_note'), hint: 'Describe the category', lines: 2, onChanged: _refresh),
              ],
            ],
          ),
        ),
        StepCard(
          child: PhotoSlot(label: 'Picture - front side & sign board', photos: _p('front'), onChanged: _refresh, max: 2),
        ),
        StepCard(
          title: 'Where it sits',
          child: Column(
            children: [
              _dropdown('Beat *', _routes, _a['beat_id'] as int?, (v) => setState(() => _a['beat_id'] = v)),
              const SizedBox(height: 10),
              _dropdown('Territory *', _cities, _a['district_id'] as int?,
                  (v) => setState(() => _a['district_id'] = v)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _autoField(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted))),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 8),
              const Text('auto', style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
            ],
          ),
        ),
      );

  Widget _dropdown(String label, List<Map<String, dynamic>> items, int? value, ValueChanged<int?> onChanged) =>
      DropdownButtonFormField<int>(
        initialValue: items.any((i) => i['id'] == value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          for (final i in items)
            DropdownMenuItem(
                value: i['id'] as int, child: Text('${i['name']}', maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      );

  String? _checkContact() {
    if (_s('name').isEmpty) return 'Give the outlet a name.';
    final category = _a['category'] as String?;
    if (category == null) return 'Choose the outlet category.';
    if (category == 'others' && _s('category_note').isEmpty) return 'Describe the outlet category.';
    if (_p('front').isEmpty) return 'Take the photo of the front and sign board.';
    if (_a['beat_id'] == null) return 'Choose the beat.';
    if (_a['district_id'] == null) return 'Choose the territory.';
    return null;
  }

  // ------------------------------------------------------------------ the meeting
  Widget _stepPerson() {
    final designation = _a['person'] as String?;
    return Column(
      children: [
        StepCard(
          title: 'Person met - designation *',
          child: Choice(
              options: _list('person_met'),
              value: designation,
              onChanged: (v) => setState(() => _a['person'] = v)),
        ),
        if (designation == 'others')
          StepCard(
            title: 'Description *',
            child: TextAnswer(controller: _t('person_note'), hint: 'e.g. Purchase in-charge', lines: 2, onChanged: _refresh),
          ),
      ],
    );
  }

  String? _checkPerson() {
    final designation = _a['person'] as String?;
    if (designation == null) return 'Say who was met.';
    if (designation == 'others' && _s('person_note').isEmpty) return 'Describe who was met.';
    return null;
  }

  Widget _stepSamples() {
    final given = _a['samples'] as bool?;
    return Column(
      children: [
        StepCard(
          title: 'Samples given? *',
          child: YesNo(value: given, onChanged: (v) => setState(() => _a['samples'] = v)),
        ),
        if (given == true)
          StepCard(
            title: 'Sample quantity *',
            child: QtyGrid(products: _flavours, values: _q('sample'), onChanged: _refresh),
          ),
        if (given == false)
          StepCard(
            title: 'Reason *',
            child: TextAnswer(controller: _t('samples_reason'), hint: 'Type here', onChanged: _refresh),
          ),
      ],
    );
  }

  String? _checkSamples() {
    final given = _a['samples'] as bool?;
    if (given == null) return 'Say whether samples were given.';
    if (given) return _q('sample').values.any((v) => v > 0) ? null : 'Enter the quantity of samples given.';
    return _s('samples_reason').isEmpty ? 'Say why no samples were given.' : null;
  }

  Widget _stepMargin() => StepCard(
        title: 'Margin discussed *',
        child: TextAnswer(controller: _t('margin'), hint: 'What margin was discussed?', lines: 4, onChanged: _refresh),
      );

  Widget _stepUpdate() => StepCard(
        title: 'Meeting update *',
        child: TextAnswer(controller: _t('update'), hint: 'What happened in the meeting?', lines: 5, onChanged: _refresh),
      );

  Widget _stepLeadOutcome() {
    final code = _a['lead_outcome'] as String?;
    final date = _a['follow_date'] as DateTime?;
    return Column(
      children: [
        StepCard(
          title: 'Outcome *',
          child: Choice(
              options: _list('lead_outcomes'),
              value: code,
              onChanged: (v) => setState(() => _a['lead_outcome'] = v)),
        ),
        if (code == 'follow_up')
          StepCard(
            title: 'Follow-up date *',
            note: 'The visit is added to your route plan on this date.',
            child: OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date ?? DateTime.now().add(const Duration(days: 1)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _a['follow_date'] = picked);
              },
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(date == null ? 'Choose the date' : fmtDate(date)),
            ),
          ),
        if (code == 'not_interested')
          StepCard(
            title: 'Reason for Not Interested *',
            note: 'The outlet is taken off the beat plan.',
            child: TextAnswer(controller: _t('not_interested'), hint: 'Type here', onChanged: _refresh),
          ),
        if (code == 'onboarded')
          const StepCard(
            tint: AppColors.success,
            child: Text(
                'After you submit, the outlet form opens to fill the remaining details, then a Client Visit starts.',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  String? _checkLeadOutcome() {
    final code = _a['lead_outcome'] as String?;
    if (code == null) return 'Choose the outcome.';
    if (code == 'follow_up' && _a['follow_date'] == null) return 'Choose the follow-up date.';
    if (code == 'not_interested' && _s('not_interested').isEmpty) return 'Say why the lead is not interested.';
    return null;
  }

  Widget _stepMeetingResult() {
    final code = _a['result'] as String?;
    return Column(
      children: [
        StepCard(
          title: 'How did it go? *',
          child: Choice(
              options: _list('meeting_results'),
              value: code,
              onChanged: (v) => setState(() => _a['result'] = v)),
        ),
        if (code == 'not_available')
          const StepCard(
            tint: AppColors.warning,
            child: Text(
                'Client not available means the right decision-maker was not there. Earlier steps are still '
                'filled from the meeting with whoever was present.',
                style: TextStyle(fontSize: 12.5)),
          ),
        if (code == 'others')
          StepCard(
            title: 'Description *',
            child: TextAnswer(controller: _t('result_note'), hint: 'Type here', onChanged: _refresh),
          ),
      ],
    );
  }

  String? _checkMeetingResult() {
    final code = _a['result'] as String?;
    if (code == null) return 'Say how it went.';
    if (code == 'others' && _s('result_note').isEmpty) return 'Describe how it went.';
    return null;
  }

  // ------------------------------------------------------------------ single-screen tasks
  Widget _stepAdhoc() => Column(
        children: [
          StepCard(child: PhotoSlot(label: 'Photo', photos: _p('adhoc'), onChanged: _refresh, max: 2)),
          StepCard(
            title: 'Description *',
            note: 'Any errand on the road that is not an outlet visit.',
            child: TextAnswer(controller: _t('description'), hint: 'What did you do?', lines: 4, onChanged: _refresh),
          ),
        ],
      );

  String? _checkAdhoc() {
    if (_p('adhoc').isEmpty) return 'Take the photo.';
    return _s('description').isEmpty ? 'Describe what was done.' : null;
  }

  Widget _stepSample() {
    final source = _a['source'] as String?;
    final options = [
      {'code': 'distributor', 'name': 'Distributor'},
      {'code': 'outlet', 'name': 'Outlet'},
      if (widget.config['company_samples'] == true) {'code': 'company', 'name': 'Company'},
    ];
    // Where the person is standing is where the samples come from, unless the team
    // may also take them from company stock.
    final fromContact = widget.client != null && source != 'company';
    final contactIs = widget.client?['category_type'] == 'distributor' ? 'distributor' : 'outlet';
    return Column(
      children: [
        if (fromContact && widget.config['company_samples'] != true)
          StepCard(
            title: 'Collected from',
            child: LockedField(
              value: '${widget.client!['name']}',
              subtitle: contactIs == 'distributor' ? 'Collected from this distributor' : 'Collected from this outlet',
            ),
          )
        else if (widget.client != null)
          StepCard(
            title: 'Collected from *',
            child: Choice(
              options: [
                {'code': contactIs, 'name': 'This $contactIs: ${widget.client!['name']}'},
                {'code': 'company', 'name': 'Company'},
              ],
              value: source,
              onChanged: (v) => setState(() => _a['source'] = v),
            ),
          )
        else
          StepCard(
            title: 'Collected from *',
            child: Choice(options: options, value: source, onChanged: (v) => setState(() => _a['source'] = v)),
          ),
        if (source == 'distributor' && widget.client == null)
          StepCard(
            title: 'Distributor *',
            note: 'A debit note demand is raised: distributor to Kumbayah.',
            child: _picker(
              _a['distributor'] as Map<String, dynamic>?,
              'Choose the distributor',
              () async {
                final d = await pickFromList(context,
                    title: 'Distributor',
                    load: () async =>
                        (await Services.api.get('/api/v1/distributors') as List).cast<Map<String, dynamic>>(),
                    subtitle: (r) => '${r['city'] ?? ''}');
                if (d != null) setState(() => _a['distributor'] = d);
              },
            ),
          ),
        if (source == 'outlet' && widget.client == null)
          StepCard(
            title: 'Outlet *',
            note: 'The outlet is made good with the same pieces free, through its distributor, '
                'and a debit note is raised against that distributor.',
            child: _picker(_a['source_outlet'] as Map<String, dynamic>?, 'Choose the outlet', () async {
              final picked = await Navigator.of(context).push<Map<String, dynamic>>(
                  MaterialPageRoute(builder: (_) => const ClientsScreen(pickMode: true)));
              if (picked != null && mounted) setState(() => _a['source_outlet'] = picked);
            }),
          ),
        if (source == 'company')
          const StepCard(
            tint: AppColors.sky,
            child: Text('Issued from Kumbayah\'s own stock. No debit note and no demand is created.',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        if (source != null) ...[
          StepCard(
            title: source == 'outlet' ? 'Free bottles quantity *' : 'Sample quantity *',
            child: QtyGrid(products: _flavours, values: _q('sample'), onChanged: _refresh),
          ),
          StepCard(
            title: source == 'outlet' ? 'Description *' : 'Reason *',
            child: TextAnswer(controller: _t('reason'), hint: 'Type here', lines: 2, onChanged: _refresh),
          ),
        ],
      ],
    );
  }

  String? _checkSample() {
    final source = _a['source'] as String?;
    if (source == null) return 'Say where the samples were collected from.';
    if (source == 'distributor' && _a['distributor'] == null) return 'Choose the distributor.';
    if (source == 'outlet' && _a['source_outlet'] == null) return 'Choose the outlet the samples come from.';
    if (!_q('sample').values.any((v) => v > 0)) return 'Enter the quantity of each flavour.';
    return _s('reason').isEmpty ? 'Give the reason.' : null;
  }

  /// Where the person is checked in is fixed; only a task with no contact picks one.
  bool get _locked => widget.client != null;

  Widget _stepSupply() => Column(
        children: [
          StepCard(
            title: 'Outlet *',
            child: _locked
                ? LockedField(value: '${_client!['name']}', subtitle: asText(_client!['city']) ?? 'Checked in here')
                : _picker(_client, 'Choose the outlet', _chooseOutlet),
          ),
          StepCard(
            title: 'Materials supplied *',
            note: 'Type the quantity supplied against each item.',
            child: QtyGrid(products: _materials, values: _q('supply'), onChanged: _refresh),
          ),
          StepCard(
            child: PhotoSlot(
                label: 'Photo of installed material', photos: _p('supply'), onChanged: _refresh, max: 3),
          ),
        ],
      );

  String? _checkSupply() {
    if (_client == null) return 'Choose the outlet.';
    if (!_q('supply').values.any((v) => v > 0)) return 'Enter the material supplied.';
    return _p('supply').isEmpty ? 'Take the photo of the material supplied.' : null;
  }

  Widget _picker(Map<String, dynamic>? chosen, String hint, VoidCallback tap) => Material(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Expanded(
                  child: Text(chosen == null ? hint : '${chosen['name']}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: chosen == null ? AppColors.muted : AppColors.text)),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      );

  Future<void> _chooseOutlet() async {
    final picked = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => const ClientsScreen(pickMode: true)));
    if (picked != null && mounted) setState(() => _client = picked);
  }

  // ------------------------------------------------------------------ sending it
  List<Map<String, dynamic>> _rows(String key) => [
        for (final e in _q(key).entries) {'product_id': e.key, 'qty': e.value},
      ];

  List<Map<String, dynamic>> _photoRows() => [
        for (final entry in _photos.entries)
          for (final bytes in entry.value) {'tag': entry.key, 'data': base64Encode(bytes)},
      ];

  Map<String, dynamic> _meetingPayload() {
    final code = _a['lead_outcome'];
    final date = _a['follow_date'] as DateTime?;
    return {
      'person': {'designation': _a['person'], 'note': _s('person_note')},
      'samples': {
        'given': _a['samples'] == true,
        'lines': _rows('sample'),
        'reason': _s('samples_reason'),
      },
      'margin': _s('margin'),
      'meeting_update': _s('update'),
      'outcome': {
        'code': code,
        if (date != null) 'follow_up_date': fmtDate(date),
        'reason': _s('not_interested'),
      },
      'result': {'code': _a['result'], 'note': _s('result_note')},
    };
  }

  Map<String, dynamic> _payload(Position? pos) {
    final base = <String, dynamic>{
      'task': widget.code,
      'uuid': _uuid,
      'lat': pos?.latitude,
      'lng': pos?.longitude,
      'accuracy': pos?.accuracy,
      'at': DateTime.now().toUtc().toIso8601String(),
      'device_time': DateTime.now().toUtc().toIso8601String(),
      if (_client != null) 'partner_id': _client!['id'],
      if (widget.visit != null && widget.visit!['id'] != null) 'visit_id': widget.visit!['id'],
      'photos': _photoRows(),
    };
    switch (widget.code) {
      case 'client_visit':
        final open = _a['open'] == true;
        return {
          ...base,
          'open': open,
          if (open) ...{
            'stock': _rows('stock'),
            'demand': {
              'wanted': _a['demand'] == true,
              'reason': _s('demand_reason'),
              'order': _rows('order'),
              'free': _rows('free'),
              'free_reason': _a['free_reason'],
              'free_note': _s('free_note'),
            },
            'materials': [
              for (final m in _materials)
                {
                  'product_id': m['id'],
                  'available': _available.contains(m['id']),
                  'qty_needed': _q('needed')[m['id']] ?? 0,
                },
            ],
            'damage': {
              'any': _a['damage'] == true,
              'lines': _rows('credit'),
              'reason': _a['damage_reason'],
            },
            'outcome': _a['outcome'],
            'outcome_note': _s('outcome_note'),
          },
          'ledger': {
            'sent': _a['ledger'] == true,
            'outstanding': ((_ledger?['total'] as num?) ?? 0).toDouble(),
          },
        };
      case 'new_lead':
        return {
          ...base,
          'contact': {
            'name': _s('name'),
            'category': _a['category'],
            'category_note': _s('category_note'),
            'beat_id': _a['beat_id'],
            'district_id': _a['district_id'],
            'territory': _cities.where((c) => c['id'] == _a['district_id']).map((c) => c['name']).firstOrNull,
          },
          ..._meetingPayload(),
        };
      case 'lead_follow_up':
        return {...base, ..._meetingPayload()};
      case 'adhoc':
        return {...base, 'description': _s('description')};
      case 'sample_collection':
        return {
          ...base,
          'source': _a['source'],
          'distributor_id': (_a['distributor'] as Map?)?['id'],
          // The outlet the samples came from; the contact above is where the person stands.
          'source_partner_id': (_a['source_outlet'] as Map?)?['id'],
          'lines': _rows('sample'),
          'reason': _s('reason'),
        };
      default:
        return {...base, 'materials': _rows('supply')};
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      Position? pos;
      try {
        pos = await currentPosition(recentOk: true);
      } catch (_) {
        // A task is still worth recording without a fix.
      }
      final result = await Services.outbox.submit('/api/v1/field-tasks/submit', _payload(pos),
          label: '$_name${_client != null ? ' · ${_client!['name']}' : ''}');
      if (result.queued && widget.visit != null) await LocalState.visitClosed();
      Services.refresh.value++;
      if (!mounted) return;
      final done = result.queued ? <String, dynamic>{} : result.map;
      if (result.queued) {
        showSnack(context, '$_name saved on the phone. It will sync when you are back online.');
      } else {
        await _showDone(done);
      }
      if (mounted) Navigator.of(context).pop(done);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Going back while checked in. There is no back: the visit ends when the task is
  /// submitted. A way out is still kept for the day it cannot be - a shop that has
  /// burnt down, a phone that cannot take the photo - but it is a deliberate act
  /// with a reason, and it is on the record.
  Future<void> _stayCheckedIn() async {
    final out = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: const Icon(Icons.lock_clock_rounded, color: AppColors.primary, size: 34),
        title: const Text('You are checked in'),
        content: const Text('Finish the steps and submit to check out. You cannot go anywhere else until then.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Cannot finish', style: TextStyle(color: AppColors.danger)),
          ),
          FilledButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Keep going')),
        ],
      ),
    );
    if (out != true || !mounted) return;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Check out without finishing?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nothing you entered is saved, and your manager will see why.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: reason,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason *', isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Check out')),
        ],
      ),
    );
    final why = reason.text.trim();
    reason.dispose();
    if (confirmed != true || !mounted) return;
    if (why.isEmpty) {
      showSnack(context, 'Give the reason.');
      return;
    }
    try {
      await Services.api.post('/api/v1/visits/check-out', {
        'visit_uuid': widget.visit?['uuid'],
        'task': true,
        'outcome': 'other',
        'note': 'Left the task unfinished: $why',
      });
      Services.refresh.value++;
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  static const _taskIcons = <String, IconData>{
    'client_visit': Icons.storefront_rounded,
    'new_lead': Icons.person_add_alt_1_rounded,
    'lead_follow_up': Icons.event_repeat_rounded,
    'adhoc': Icons.bolt_rounded,
    'sample_collection': Icons.science_rounded,
    'marketing_supply': Icons.campaign_rounded,
  };

  /// What task this is, which step of it, how far through, and for whom.
  Widget _header(_Step step, List<_Step> steps, String? who) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                    child: Icon(_taskIcons[widget.code] ?? Icons.task_alt_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                        Text('Step ${step.number} - ${step.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                    child: Text('${step.number}/$_total',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // One segment per screen, filled as they are done.
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          height: 5,
                          margin: EdgeInsets.only(right: i == steps.length - 1 ? 0 : 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: i < _index ? 1 : i == _index ? 0.65 : 0.25),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (who != null) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.place_rounded, size: 15, color: Colors.white),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(who,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Back and Next, with what is still missing said plainly above them.
  Widget _bottomBar(String? problem, bool last) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (problem != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(problem,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  if (_index > 0) ...[
                    SizedBox(
                      height: 52,
                      width: 52,
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => setState(() => _index--),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: GradientButton(
                      label: last ? 'Submit' : 'Next',
                      icon: last ? Icons.check_rounded : Icons.arrow_forward_rounded,
                      busy: _busy,
                      onPressed: problem != null || _busy
                          ? null
                          : last
                              ? _submit
                              : () => setState(() => _index++),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A task is finished: say so, and name what it set going.
  Future<void> _showDone(Map<String, dynamic> result) {
    final demands = ((result['demands'] as List?) ?? []).cast<Map>();
    final notes = ((result['notes'] as List?) ?? []).cast<Map>();
    final lines = <String>[
      for (final d in demands) 'Demand ${d['name']} raised',
      for (final n in notes) '${n['kind'] == 'credit' ? 'Credit' : 'Debit'} note demand ${n['name']} raised',
      if (result['onboard'] == true) 'Ready to onboard: the outlet form opens next',
    ];
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.13), shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 38, color: AppColors.success),
              ),
              const SizedBox(height: 14),
              Text('$_name done', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 4),
              Text(
                  widget.visit != null || result['name'] != null
                      ? 'Recorded as ${result['name'] ?? 'a task'}${widget.visit != null ? ' and you are checked out.' : '.'}'
                      : 'Recorded.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              if (lines.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                              const SizedBox(width: 8),
                              Expanded(child: Text(line, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: GradientButton(label: 'Done', icon: Icons.done_all_rounded, onPressed: () => Navigator.pop(sheet)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ the screen
  @override
  Widget build(BuildContext context) {
    final steps = _steps();
    if (_index >= steps.length) _index = steps.length - 1;
    final step = steps[_index];
    final problem = step.check();
    final last = _index == steps.length - 1;
    final who = _client == null ? null : '${_client!['name']}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Checked in: the way out is checking out, which is submitting the task.
        if (widget.visit != null) {
          await _stayCheckedIn();
          return;
        }
        final leave = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Leave this task?'),
            content: const Text('What you have entered will be lost.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Stay')),
              FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Leave')),
            ],
          ),
        );
        if (leave == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(who == null ? 128 : 160),
          child: _header(step, steps, who),
        ),
        bottomNavigationBar: _bottomBar(problem, last),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
          children: [step.body()],
        ),
      ),
    );
  }
}

/// A row per marketing material: is it there, and how many more are wanted.
class _MaterialRows extends StatefulWidget {
  const _MaterialRows({
    required this.materials,
    required this.available,
    required this.needed,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> materials;
  final Set<int> available;
  final Map<int, double> needed;
  final VoidCallback onChanged;

  @override
  State<_MaterialRows> createState() => _MaterialRowsState();
}

class _MaterialRowsState extends State<_MaterialRows> {
  final Map<int, TextEditingController> _controllers = {};

  TextEditingController _c(int id) => _controllers.putIfAbsent(id, () {
        final known = widget.needed[id];
        return TextEditingController(text: known == null || known == 0 ? '' : fmtQty(known));
      });

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.materials.isEmpty) {
      return const Text('No marketing material is set up yet. The office marks the categories.',
          style: TextStyle(color: AppColors.muted, fontSize: 12.5));
    }
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(child: Text('Material', style: TextStyle(fontSize: 11.5, color: AppColors.muted))),
              SizedBox(width: 70, child: Text('Available', style: TextStyle(fontSize: 11.5, color: AppColors.muted))),
              SizedBox(width: 70, child: Text('Qty needed', style: TextStyle(fontSize: 11.5, color: AppColors.muted))),
            ],
          ),
        ),
        for (final m in widget.materials)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('${m['name']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
                SizedBox(
                  width: 70,
                  child: Checkbox(
                    value: widget.available.contains(m['id']),
                    onChanged: (on) {
                      setState(() => on == true ? widget.available.add(m['id'] as int) : widget.available.remove(m['id']));
                      widget.onChanged();
                    },
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _c(m['id'] as int),
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (text) {
                      final v = double.tryParse(text.trim());
                      if (v == null || v <= 0) {
                        widget.needed.remove(m['id']);
                      } else {
                        widget.needed[m['id'] as int] = v;
                      }
                      widget.onChanged();
                    },
                    decoration: InputDecoration(
                      hintText: '0',
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
