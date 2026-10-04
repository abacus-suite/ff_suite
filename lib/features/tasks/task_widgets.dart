import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/geo_camera.dart';
import '../../core/theme.dart';

/// What a card is about, read off its title, so each one carries a fitting icon.
IconData _iconFor(String title) {
  final s = title.toLowerCase();
  if (s.contains('open')) return Icons.storefront_rounded;
  if (s.contains('photo') || s.contains('picture')) return Icons.photo_camera_rounded;
  if (s.contains('stock')) return Icons.inventory_2_rounded;
  if (s.contains('free')) return Icons.card_giftcard_rounded;
  if (s.contains('demand') || s.contains('order')) return Icons.shopping_cart_rounded;
  if (s.contains('material')) return Icons.campaign_rounded;
  if (s.contains('receivable') || s.contains('ledger')) return Icons.account_balance_wallet_rounded;
  if (s.contains('damage') || s.contains('credit')) return Icons.report_gmailerrorred_rounded;
  if (s.contains('person')) return Icons.person_rounded;
  if (s.contains('sample')) return Icons.science_rounded;
  if (s.contains('how did') || s.contains('outcome')) return Icons.flag_rounded;
  if (s.contains('date')) return Icons.event_rounded;
  if (s.contains('distributor')) return Icons.local_shipping_rounded;
  if (s.contains('outlet') || s.contains('collected')) return Icons.store_mall_directory_rounded;
  if (s.contains('categor') || s.contains('where')) return Icons.category_rounded;
  if (s.contains('reason') || s.contains('description') || s.contains('margin') || s.contains('meeting') ||
      s.contains('notes')) {
    return Icons.edit_note_rounded;
  }
  return Icons.checklist_rounded;
}

/// The card a step's content sits on: a tinted icon, the question, and a soft lift.
class StepCard extends StatelessWidget {
  const StepCard({super.key, required this.child, this.title, this.note, this.tint, this.icon});

  final Widget child;
  final String? title;
  final String? note;
  final Color? tint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final accent = tint ?? AppColors.primary;
    final required = title?.trimRight().endsWith('*') ?? false;
    final clean = required ? title!.trimRight().substring(0, title!.trimRight().length - 1).trimRight() : title;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      decoration: BoxDecoration(
        color: tint?.withValues(alpha: 0.08) ?? Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: tint == null ? null : Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: tint == null
            ? [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 6))]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (clean != null)
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon ?? _iconFor(clean), size: 17, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: clean, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    if (required)
                      const TextSpan(
                          text: '  Required',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.danger)),
                  ])),
                ),
              ],
            ),
          if (note != null) ...[
            const SizedBox(height: 7),
            Text(note!, style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.35)),
          ],
          if (clean != null || note != null) const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// A value that is fixed and cannot be changed, with the lock to say so.
///
/// For the contact the person is already checked in at: it is who the task is
/// for, so letting it be picked again would only invite a mistake.
class LockedField extends StatelessWidget {
  const LockedField({super.key, required this.value, this.subtitle});

  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded, size: 20, color: AppColors.success),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text(subtitle ?? 'Checked in here',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                ],
              ),
            ),
            const Icon(Icons.lock_rounded, size: 17, color: AppColors.muted),
          ],
        ),
      );
}

/// Yes or No, side by side, nothing chosen until one is tapped.
class YesNo extends StatelessWidget {
  const YesNo({super.key, required this.value, required this.onChanged, this.yes = 'Yes', this.no = 'No'});

  final bool? value;
  final ValueChanged<bool> onChanged;
  final String yes;
  final String no;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: _pill(yes, value == true, AppColors.success, () => onChanged(true))),
          const SizedBox(width: 10),
          Expanded(child: _pill(no, value == false, AppColors.danger, () => onChanged(false))),
        ],
      );

  Widget _pill(String label, bool on, Color tint, VoidCallback tap) => Material(
        color: on ? tint : AppColors.background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: tap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? tint : AppColors.border, width: 1.4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (on) ...[
                  const Icon(Icons.check_circle_rounded, size: 18, color: Colors.white),
                  const SizedBox(width: 7),
                ],
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15.5, color: on ? Colors.white : AppColors.text)),
              ],
            ),
          ),
        ),
      );
}

/// One answer out of a short list.
class Choice extends StatelessWidget {
  const Choice({super.key, required this.options, required this.value, required this.onChanged});

  /// Each is {code, name}.
  final List<Map<String, dynamic>> options;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 9,
        runSpacing: 9,
        children: [
          for (final o in options) _pill('${o['name']}', value == o['code'], () => onChanged('${o['code']}')),
        ],
      );

  Widget _pill(String label, bool on, VoidCallback tap) => Material(
        color: on ? AppColors.primary : AppColors.background,
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: tap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: on ? AppColors.primary : AppColors.border, width: 1.3),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (on) ...[
                  const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                ],
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5, color: on ? Colors.white : AppColors.text)),
              ],
            ),
          ),
        ),
      );
}

/// Free text, kept in a controller that outlives the screen it is on.
class TextAnswer extends StatelessWidget {
  const TextAnswer({super.key, required this.controller, required this.hint, this.lines = 3, this.onChanged});

  final TextEditingController controller;
  final String hint;
  final int lines;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        maxLines: lines,
        minLines: lines > 1 ? 2 : 1,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => onChanged?.call(),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      );
}

/// A quantity beside each product, typed straight in.
///
/// Counting and ordering are reading numbers off shelves, so the number goes
/// into the row and the keyboard walks down the list. When [requireAll] is set
/// every box has to be filled - a zero is an answer, an empty box is not.
class QtyGrid extends StatefulWidget {
  const QtyGrid({
    super.key,
    required this.products,
    required this.values,
    required this.onChanged,
    this.requireAll = false,
    this.unit,
  });

  final List<Map<String, dynamic>> products;

  /// product id -> quantity. Absent means not filled in.
  final Map<int, double> values;
  final VoidCallback onChanged;
  final bool requireAll;
  final String? unit;

  @override
  State<QtyGrid> createState() => _QtyGridState();
}

class _QtyGridState extends State<QtyGrid> {
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, FocusNode> _nodes = {};

  TextEditingController _controller(int id) => _controllers.putIfAbsent(id, () {
        final known = widget.values[id];
        return TextEditingController(text: known == null ? '' : fmtQty(known));
      });

  FocusNode _node(int id) => _nodes.putIfAbsent(id, FocusNode.new);

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _typed(int id, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      widget.values.remove(id);
    } else {
      final value = double.tryParse(trimmed);
      if (value != null && value >= 0) widget.values[id] = value;
    }
    widget.onChanged();
    setState(() {});
  }

  void _fillEmpty() {
    for (final p in widget.products) {
      final id = p['id'] as int;
      if (!widget.values.containsKey(id)) {
        widget.values[id] = 0;
        _controller(id).text = '0';
      }
    }
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.products.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No flavours are set up yet. The office marks the categories to count.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
      );
    }
    final empty = widget.products.where((p) => !widget.values.containsKey(p['id'])).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.products.length; i++) _row(i),
        if (widget.requireAll && empty > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text('$empty left to fill. Enter 0 where there is none.',
                      style: const TextStyle(fontSize: 12, color: AppColors.warning, fontWeight: FontWeight.w600)),
                ),
                TextButton(onPressed: _fillEmpty, child: const Text('Fill empty with 0')),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(int index) {
    final p = widget.products[index];
    final id = p['id'] as int;
    final filled = widget.values.containsKey(id);
    final code = asText(p['code']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      decoration: BoxDecoration(
        color: filled ? AppColors.primary.withValues(alpha: 0.05) : AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: filled ? AppColors.primary.withValues(alpha: 0.25) : Colors.transparent),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(code ?? '${p['name']}'.characters.take(2).toString().toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${p['name']}',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: TextField(
              controller: _controller(id),
              focusNode: _node(id),
              onChanged: (text) => _typed(id, text),
              onSubmitted: (_) {
                if (index + 1 < widget.products.length) {
                  _node(widget.products[index + 1]['id'] as int).requestFocus();
                }
              },
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.next,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              decoration: InputDecoration(
                hintText: widget.requireAll ? '' : '0',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Photos taken with the geo-tagged camera, one list per purpose.
class PhotoSlot extends StatefulWidget {
  const PhotoSlot({
    super.key,
    required this.label,
    required this.photos,
    required this.onChanged,
    this.required = true,
    this.max = 3,
  });

  final String label;
  final List<Uint8List> photos;
  final VoidCallback onChanged;
  final bool required;
  final int max;

  @override
  State<PhotoSlot> createState() => _PhotoSlotState();
}

class _PhotoSlotState extends State<PhotoSlot> {
  Future<void> _add() async {
    if (widget.photos.length >= widget.max) return;
    final bytes = await openGeoCamera(title: widget.label);
    if (bytes == null || !mounted) return;
    setState(() => widget.photos.add(bytes));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                if (widget.required)
                  const Text(' *', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < widget.photos.length; i++)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(widget.photos[i], width: 84, height: 84, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: InkWell(
                          onTap: () {
                            setState(() => widget.photos.removeAt(i));
                            widget.onChanged();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded, size: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (widget.photos.length < widget.max)
                  InkWell(
                    onTap: _add,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                            child: const Icon(Icons.add_a_photo_rounded, size: 18, color: AppColors.primary),
                          ),
                          const SizedBox(height: 5),
                          const Text('Take', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
}

/// Chooses one item from a long list the server holds.
Future<Map<String, dynamic>?> pickFromList(
  BuildContext context, {
  required String title,
  required Future<List<Map<String, dynamic>>> Function() load,
  String Function(Map<String, dynamic>)? subtitle,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => _ListPicker(title: title, load: load, subtitle: subtitle),
  );
}

class _ListPicker extends StatefulWidget {
  const _ListPicker({required this.title, required this.load, this.subtitle});

  final String title;
  final Future<List<Map<String, dynamic>>> Function() load;
  final String Function(Map<String, dynamic>)? subtitle;

  @override
  State<_ListPicker> createState() => _ListPickerState();
}

class _ListPickerState extends State<_ListPicker> {
  List<Map<String, dynamic>> _all = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.load().then((rows) {
      if (mounted) setState(() => _all = rows);
    }).catchError((Object e) {
      if (mounted) showSnack(context, e.toString());
    }).whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty ? _all : _all.where((r) => '${r['name']}'.toLowerCase().contains(q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded), hintText: 'Search', isDense: true),
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text('${shown[i]['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: widget.subtitle == null ? null : Text(widget.subtitle!(shown[i])),
                  onTap: () => Navigator.pop(context, shown[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
