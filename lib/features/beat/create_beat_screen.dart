import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';

/// Screen to create a new Beat matching client design specifications.
class CreateBeatScreen extends StatefulWidget {
  const CreateBeatScreen({super.key});

  @override
  State<CreateBeatScreen> createState() => _CreateBeatScreenState();
}

class _CreateBeatScreenState extends State<CreateBeatScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  List<Map<String, dynamic>> _territories = [];
  Map<String, dynamic>? _territory;
  final Set<int> _outlets = {};
  String _schedule = 'recurrent';
  DateTime _date = DateTime.now();
  final Set<int> _days = {0, 3}; // Monday and Thursday default, as in mockup
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadTerritories();
  }

  Future<void> _loadTerritories() async {
    try {
      final list = await Services.api.get('/api/v1/territories') as List;
      if (mounted) {
        setState(() {
          _territories = list.cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {
      // Offline or network error
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  String _formatDay(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day.toString().padLeft(2, '0')}-${months[d.month - 1]}-${d.year}';
  }

  Widget _label(String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Color(0xFF0F1B3D),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          children: [
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF1E5BE3), width: 1.5),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickOutlets() async {
    if (_territory == null) {
      showProblem(context, 'Please choose a territory first.');
      return;
    }
    final allOutlets = ((_territory!['outlets'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (allOutlets.isEmpty) {
      showProblem(context, 'No outlets found for this territory.');
      return;
    }

    final tempSelected = Set<int>.from(_outlets);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? allOutlets
                : allOutlets.where((o) => '${o['name']} ${o['city'] ?? ''}'.toLowerCase().contains(q)).toList();

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Select Outlets (${tempSelected.length}/${allOutlets.length})',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                if (tempSelected.length == allOutlets.length) {
                                  tempSelected.clear();
                                } else {
                                  tempSelected.addAll(allOutlets.map((o) => o['id'] as int));
                                }
                              });
                            },
                            child: Text(tempSelected.length == allOutlets.length ? 'Clear' : 'Select all'),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          hintText: 'Search outlet or city...',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        onChanged: (val) => setSheetState(() => query = val),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No matching outlets', style: TextStyle(color: AppColors.muted)))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, index) {
                                final outlet = filtered[index];
                                final id = outlet['id'] as int;
                                final isChecked = tempSelected.contains(id);
                                return CheckboxListTile(
                                  value: isChecked,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  title: Text(
                                    '${outlet['name']}',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  subtitle: outlet['city'] != null ? Text('${outlet['city']}', style: const TextStyle(fontSize: 12)) : null,
                                  onChanged: (val) {
                                    setSheetState(() {
                                      if (val == true) {
                                        tempSelected.add(id);
                                      } else {
                                        tempSelected.remove(id);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1E5BE3),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (mounted) {
      setState(() {
        _outlets
          ..clear()
          ..addAll(tempSelected);
      });
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showProblem(context, 'Please enter Beat name.');
      return;
    }
    final code = _code.text.trim();
    if (code.isEmpty) {
      showProblem(context, 'Please enter Beat code.');
      return;
    }
    if (_territory == null) {
      showProblem(context, 'Please select a Territory.');
      return;
    }
    if (_outlets.isEmpty) {
      showProblem(context, 'Please select at least one outlet.');
      return;
    }
    if (_schedule == 'recurrent' && _days.isEmpty) {
      showProblem(context, 'Please choose at least one day for repeat.');
      return;
    }

    setState(() => _busy = true);
    try {
      final beat = await Services.api.post('/api/v1/beats', {
        'name': name,
        'code': code,
        'territory_id': _territory!['id'],
        if (_territory!['district_id'] != null) 'district_id': _territory!['district_id'],
        'partner_ids': _outlets.toList(),
        'schedule': _schedule,
        'date': fmtDate(_date),
        if (_schedule == 'recurrent') 'weekdays': _days.toList()..sort(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).pop(beat);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F1B3D)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Create Beat',
          style: TextStyle(
            color: Color(0xFF0F1B3D),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            height: 50,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E5BE3), Color(0xFF00C4B4)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _busy ? null : _save,
                  child: Center(
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Text(
                            'Save Beat',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: [
          // Day
          _label('Day'),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatDay(_date),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF0F1B3D),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Icon(Icons.calendar_today_outlined, size: 20, color: Color(0xFF64748B)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Beat name *
          _label('Beat name', required: true),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 14, color: Color(0xFF0F1B3D)),
            decoration: _fieldDecoration('Beat 10 – Palarivattom'),
          ),
          const SizedBox(height: 16),

          // Beat code *
          _label('Beat code', required: true),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 14, color: Color(0xFF0F1B3D)),
            decoration: _fieldDecoration('KOC-B10'),
          ),
          const SizedBox(height: 16),

          // Territory *
          _label('Territory', required: true),
          DropdownButtonFormField<int>(
            initialValue: _territory?['id'] as int?,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
            decoration: _fieldDecoration('Choose a territory'),
            items: [
              for (final t in _territories)
                DropdownMenuItem(
                  value: t['id'] as int,
                  child: Text(
                    '${t['name']}',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF0F1B3D)),
                  ),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _territory = _territories.firstWhere((t) => t['id'] == v);
                final outletsList = ((_territory!['outlets'] as List?) ?? []).cast<Map<String, dynamic>>();
                _outlets
                  ..clear()
                  ..addAll(outletsList.map((o) => o['id'] as int));
              });
            },
          ),
          const SizedBox(height: 16),

          // Outlets (filtered by territory) *
          _label('Outlets (filtered by territory)', required: true),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _pickOutlets,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _territory == null
                          ? 'Select territory first'
                          : '${_outlets.length} outlets selected',
                      style: TextStyle(
                        fontSize: 14,
                        color: _territory == null ? const Color(0xFF94A3B8) : const Color(0xFF0F1B3D),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Toggle: One time / Recurrent
          Row(
            children: [
              _buildPill(
                label: 'One time',
                isSelected: _schedule == 'one_time',
                onTap: () => setState(() => _schedule = 'one_time'),
              ),
              const SizedBox(width: 10),
              _buildPill(
                label: 'Recurrent',
                isSelected: _schedule == 'recurrent',
                onTap: () => setState(() => _schedule = 'recurrent'),
              ),
            ],
          ),

          // Repeat on
          if (_schedule == 'recurrent') ...[
            const SizedBox(height: 16),
            _label('Repeat on'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (int i = 0; i < 7; i++)
                  _buildDayCircle(
                    letter: dayLetters[i],
                    isSelected: _days.contains(i),
                    onTap: () {
                      setState(() {
                        if (_days.contains(i)) {
                          _days.remove(i);
                        } else {
                          _days.add(i);
                        }
                      });
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPill({required String label, required bool isSelected, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E5BE3) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: isSelected ? null : Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF334155),
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayCircle({required String letter, required bool isSelected, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E5BE3) : Colors.white,
            shape: BoxShape.circle,
            border: isSelected ? null : Border.all(color: const Color(0xFFE2E8F0)),
          ),
          alignment: Alignment.center,
          child: Text(
            letter,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF334155),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
