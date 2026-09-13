import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/photos.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

const _reasons = [
  ('damaged', 'Damaged', Icons.broken_image_rounded),
  ('expired', 'Expired', Icons.event_busy_rounded),
  ('near_expiry', 'Near expiry', Icons.hourglass_bottom_rounded),
  ('wrong_item', 'Wrong item', Icons.swap_horiz_rounded),
  ('unsold', 'Unsold', Icons.inventory_rounded),
  ('other', 'Other', Icons.more_horiz_rounded),
];

/// Goods coming back from the outlet: what, how many, why, with photos.
class ReturnScreen extends StatefulWidget {
  const ReturnScreen({super.key, required this.client});

  final Map<String, dynamic> client;

  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  final _uuid = const Uuid().v4();
  final _search = TextEditingController();
  final _note = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  final Map<int, double> _qty = {};
  final Map<int, Map<String, dynamic>> _known = {};
  final List<Uint8List> _photos = [];
  String _reason = 'damaged';
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await Services.api.get('/api/v1/products', query: {'limit': 300}) as Map<String, dynamic>;
      final products = ((data['products'] as List?) ?? []).cast<Map<String, dynamic>>();
      for (final p in products) {
        _known[p['id'] as int] = p;
      }
      if (mounted) setState(() => _products = products);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _set(int id, double qty) => setState(() => qty <= 0 ? _qty.remove(id) : _qty[id] = qty);

  Future<void> _addPhoto() async {
    if (_photos.length >= 6) return;
    final bytes = await takePhoto(ImageSource.camera);
    if (bytes != null && mounted) setState(() => _photos.add(bytes));
  }

  double get _total => _qty.entries.fold(0.0, (sum, e) => sum + e.value * (((_known[e.key]?['price']) as num?) ?? 0));

  Future<void> _submit() async {
    if (_qty.isEmpty) {
      showSnack(context, 'Add the products that are coming back.');
      return;
    }
    if ((_reason == 'damaged' || _reason == 'expired') && _photos.isEmpty) {
      showSnack(context, 'Take a photo of the ${_reason == 'damaged' ? 'damage' : 'expiry date'}.');
      return;
    }
    setState(() => _busy = true);
    try {
      double? lat, lng;
      try {
        final pos = await currentPosition();
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {}
      final result = await Services.outbox.submit('/api/v1/returns', {
        'uuid': _uuid,
        'partner_id': widget.client['id'],
        'reason': _reason,
        'note': _note.text.trim(),
        'lines': [for (final e in _qty.entries) {'product_id': e.key, 'qty': e.value}],
        'photos': _photos.map(base64Encode).toList(),
        'lat': lat,
        'lng': lng,
      }, label: 'Return · ${widget.client['name']}');
      if (!mounted) return;
      if (!result.queued) showSnack(context, 'Return ${result.map['name']} sent for approval');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final shown = q.isEmpty
        ? _products
        : _products.where((p) => '${p['name']} ${p['sku'] ?? ''}'.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Return · ${widget.client['name']}')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GradientButton(
            label: _qty.isEmpty ? 'Send return' : 'Send return · ${_qty.length} item${_qty.length == 1 ? '' : 's'} · ${fmtMoney(_total)}',
            icon: Icons.assignment_return_rounded,
            busy: _busy,
            onPressed: _submit,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text('Why is it coming back?', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _reasons)
                ChoiceChip(
                  avatar: Icon(r.$3, size: 18, color: _reason == r.$1 ? AixoloColors.primary : AixoloColors.muted),
                  label: Text(r.$2),
                  selected: _reason == r.$1,
                  onSelected: (_) => setState(() => _reason = r.$1),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Photos', style: TextStyle(fontWeight: FontWeight.w800)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _photos.length >= 6 ? null : _addPhoto,
                        icon: const Icon(Icons.photo_camera_rounded),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  if (_photos.isNotEmpty)
                    SizedBox(
                      height: 76,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var i = 0; i < _photos.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onLongPress: () => setState(() => _photos.removeAt(i)),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(_photos[i], width: 76, height: 76, fit: BoxFit.cover),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search product', isDense: true),
          ),
          if (_loading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
          for (final p in shown)
            Builder(builder: (context) {
              final id = p['id'] as int;
              final qty = _qty[id] ?? 0;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text('${p['name']}', style: TextStyle(fontWeight: qty > 0 ? FontWeight.w800 : FontWeight.w500)),
                subtitle: Text([if (p['sku'] != null) p['sku'], fmtMoney(p['price'] as num?)].join(' · ')),
                trailing: qty == 0
                    ? IconButton.filledTonal(onPressed: () => _set(id, 1), icon: const Icon(Icons.add))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(onPressed: () => _set(id, qty - 1), icon: const Icon(Icons.remove_circle_outline)),
                          Text(fmtQty(qty), style: const TextStyle(fontWeight: FontWeight.w800)),
                          IconButton(onPressed: () => _set(id, qty + 1), icon: const Icon(Icons.add_circle_outline)),
                        ],
                      ),
              );
            }),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Note (batch, what the outlet said…)'),
          ),
        ],
      ),
    );
  }
}
