import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/geo_camera.dart';
import '../../core/theme.dart';

/// A white card the step content sits on.
class StepCard extends StatelessWidget {
  const StepCard({super.key, required this.child, this.title, this.note, this.tint});

  final Widget child;
  final String? title;
  final String? note;
  final Color? tint;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        decoration: BoxDecoration(
          color: tint?.withValues(alpha: 0.07) ?? Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: tint == null ? null : Border.all(color: tint!.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Text(title!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            if (note != null) ...[
              const SizedBox(height: 3),
              Text(note!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
            if (title != null || note != null) const SizedBox(height: 10),
            child,
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
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: tap,
          child: Container(
            height: 46,
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15, color: on ? Colors.white : AppColors.text)),
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
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in options)
            ChoiceChip(
              label: Text('${o['name']}'),
              selected: value == o['code'],
              onSelected: (_) => onChanged('${o['code']}'),
            ),
        ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
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
                fillColor: filled ? AppColors.primary.withValues(alpha: 0.08) : AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide.none),
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
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_rounded, color: AppColors.primary),
                          SizedBox(height: 4),
                          Text('Take', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
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
