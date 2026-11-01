import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Screen to create a new Beat matching client design specifications.
class CreateBeatScreen extends StatefulWidget {
  const CreateBeatScreen({super.key, this.member, this.memberName});

  /// A manager drawing the beat for somebody in the team: their id and name. The beat is theirs, with no approval.
  final String? member;
  final String? memberName;

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

  /// Recurrent only: Yes repeats on the chosen weekdays; No keeps the beat in my list without fixed days.
  bool _repeat = true;
  DateTime _date = DateTime.now();

  /// Recurrent with Repeat on? No: the days the beat is planned for (one or many). Until the person picks,
  /// it is the Day field's date.
  Set<DateTime>? _plannedPicks;
  List<DateTime> get _plannedDays {
    final days = (_plannedPicks ?? {DateUtils.dateOnly(_date)}).toList()..sort();
    return days;
  }
  final Set<int> _days = {0, 3}; // Monday and Thursday default, as in mockup
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadTerritories();
  }

  Future<void> _loadTerritories() async {
    try {
      final list = await Services.api.get('/api/v1/territories',
          query: {if (widget.member != null) 'member': widget.member}) as List;
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

  /// Add one more planned day (today or later); the same day twice is kept once.
  Future<void> _addPlanned() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final last = _plannedDays.isEmpty ? today : _plannedDays.last;
    final picked = await showDatePicker(
      context: context,
      initialDate: last.isBefore(today) ? today : last,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Add a planned day',
    );
    if (picked != null && mounted) {
      setState(() => _plannedPicks = {..._plannedDays, DateUtils.dateOnly(picked)});
    }
  }

  void _removePlanned(DateTime day) {
    setState(() => _plannedPicks = {..._plannedDays}..remove(day));
  }

  Future<void> _pickOutlets() async {
    if (_territory == null) {
      showProblem(context, 'Please choose a District / Territory first.');
      return;
    }
    List<Map<String, dynamic>> allOutlets = ((_territory!['outlets'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (allOutlets.isEmpty) {
      try {
        // The contact list answers {clients: [...]}; an older server answered a bare list.
        final found = await Services.api.get('/api/v1/clients', query: {'limit': 500});
        final list = found is Map ? (found['clients'] as List? ?? const []) : (found as List? ?? const []);
        final clients = list.cast<Map<String, dynamic>>();
        final districtId = _territory!['district_id'];
        if (districtId != null) {
          final matched = clients.where((c) => c['district_id'] == districtId || c['city_id'] == districtId).toList();
          allOutlets = matched.isNotEmpty ? matched : clients;
        } else {
          allOutlets = clients;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    if (allOutlets.isEmpty) {
      showProblem(context, 'No outlets found for this District / Territory.');
      return;
    }

    // A page of its own: a search, the Area filter, and a tick per outlet.
    final picked = await Navigator.of(context).push<Set<int>>(MaterialPageRoute(
      builder: (_) => ChooseOutletsScreen(
        outlets: allOutlets,
        selected: _outlets,
        title: territoryLabel(_territory!),
        areas: ((_territory!['areas'] as List?) ?? const []).cast<Map<String, dynamic>>(),
        noAreaCount: (_territory!['no_area_count'] as num?)?.toInt(),
      ),
    ));
    if (picked != null && mounted) {
      setState(() {
        _outlets
          ..clear()
          ..addAll(picked);
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
      showProblem(context, 'Please select a District / Territory.');
      return;
    }
    if (_outlets.isEmpty) {
      showProblem(context, 'Please select at least one outlet.');
      return;
    }
    if (_schedule == 'recurrent' && _repeat && _days.isEmpty) {
      showProblem(context, 'Please choose at least one day for repeat, or choose No.');
      return;
    }
    final planDays = _schedule == 'recurrent' && !_repeat;
    final today = DateUtils.dateOnly(DateTime.now());
    if (planDays && (_plannedDays.isEmpty || _plannedDays.any((d) => d.isBefore(today)))) {
      showProblem(context, 'Choose at least one planned day, today or later.');
      return;
    }

    setState(() => _busy = true);
    try {
      final beat = await Services.api.post('/api/v1/beats', {
        if (widget.member != null) 'member': widget.member,
        'name': name,
        'code': code,
        'territory_id': _territory!['id'],
        if (_territory!['district_id'] != null) 'district_id': _territory!['district_id'],
        'partner_ids': _outlets.toList(),
        'schedule': _schedule,
        // Repeat off: the planned days, not the Day field.
        'date': fmtDate(planDays ? _plannedDays.first : _date),
        if (planDays) 'dates': [for (final d in _plannedDays) fmtDate(d)],
        // Recurrent with "Repeat on? No": kept in my beat list without fixed days.
        if (_schedule == 'recurrent') 'repeat': _repeat,
        if (_schedule == 'recurrent') 'weekdays': _repeat ? (_days.toList()..sort()) : <int>[],
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
        title: Text(
          widget.memberName == null ? 'Create Beat' : 'Create Beat · ${widget.memberName}',
          style: const TextStyle(
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

          // District / Territory *: a page of its own, with a search, as the list can be long.
          _label('District / Territory', required: true),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _pickTerritory,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _territory == null ? 'Choose a District / Territory' : territoryLabel(_territory!),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: _territory == null ? const Color(0xFF94A3B8) : const Color(0xFF0F1B3D),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Outlets *: the ones of the chosen district / territory.
          _label('Outlets', required: true),
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
                          ? 'Select District / Territory first'
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

          // Repeat on? Yes / No: recurrent only.
          if (_schedule == 'recurrent') ...[
            const SizedBox(height: 16),
            _label('Repeat on?'),
            _yesNo(),
          ],
          if (_schedule == 'recurrent' && !_repeat) ...[
            const SizedBox(height: 16),
            _label('Planned days'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final d in _plannedDays)
                  InputChip(
                    label: Text(_formatDay(d), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    onDeleted: _plannedDays.length > 1 ? () => _removePlanned(d) : null,
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add a day', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  onPressed: _addPlanned,
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                  'Pick one or more days (today or later), for example a Sunday and next Friday. The beat is planned on '
                  'those days after approval and stays in your beat list without fixed weekdays.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ),
          ],

          // Repeat on: the seven day buttons, when it repeats.
          if (_schedule == 'recurrent' && _repeat) ...[
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

  /// Yes | No, as two halves of one pill.
  Widget _yesNo() {
    Widget half(String text, bool on, VoidCallback onTap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? const Color(0xFF1E5BE3) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(text,
                  style: TextStyle(
                      color: on ? Colors.white : const Color(0xFF334155), fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(children: [
        half('Yes', _repeat, () => setState(() => _repeat = true)),
        half('No', !_repeat, () => setState(() => _repeat = false)),
      ]),
    );
  }

  /// District / Territory: picked on a page of its own; choosing one selects its outlets, as before.
  Future<void> _pickTerritory() async {
    final picked = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
      builder: (_) => TerritoryPickerScreen(territories: _territories, selectedId: _territory?['id']),
    ));
    if (picked == null || !mounted) return;
    setState(() {
      _territory = picked;
      final outletsList = ((picked['outlets'] as List?) ?? []).cast<Map<String, dynamic>>();
      _outlets
        ..clear()
        ..addAll(outletsList.map((o) => o['id'] as int));
    });
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

/// "Ernakulam · Kochi": the district first when the server names it, then the territory.
String territoryLabel(Map<String, dynamic> t) {
  final name = '${t['name'] ?? ''}';
  final district = asText(t['district_name']) ?? asText((t['district'] as Map?)?['name']);
  // A name the server already wrote as "District · Territory" is left as it is.
  if (district == null || name.contains('·')) return name;
  return '$district · $name';
}

/// District / Territory: the ones assigned to me, with a search; tapping one picks it.
class TerritoryPickerScreen extends StatefulWidget {
  const TerritoryPickerScreen({super.key, required this.territories, this.selectedId});

  final List<Map<String, dynamic>> territories;
  final Object? selectedId;

  @override
  State<TerritoryPickerScreen> createState() => _TerritoryPickerScreenState();
}

class _TerritoryPickerScreenState extends State<TerritoryPickerScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _search.text.trim().toLowerCase();
    final rows = [
      for (final t in widget.territories)
        if (needle.isEmpty || territoryLabel(t).toLowerCase().contains(needle)) t,
    ];
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('District / Territory', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          Text('Search and pick one', style: TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted),
            hintText: 'Search District / Territory…',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
          ),
        ),
        const SizedBox(height: 10),
        if (widget.territories.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No District / Territory is assigned to you yet.', style: TextStyle(color: AppColors.muted))),
          )
        else if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Nothing matches.', style: TextStyle(color: AppColors.muted))),
          ),
        for (final t in rows)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              onTap: () => Navigator.pop(context, t),
              title: Text(territoryLabel(t), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              subtitle: t['is_secondary'] == true || t['kind'] == 'secondary'
                  ? const Text('Secondary', style: TextStyle(fontSize: 11.5, color: Color(0xFF1D4ED8)))
                  : null,
              trailing: t['id'] == widget.selectedId
                  ? const Icon(Icons.check_circle_rounded, color: Color(0xFF1E5BE3))
                  : null,
            ),
          ),
        if (widget.territories.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text('Only the Districts / Territories assigned to you',
                style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: AppColors.muted)),
          ),
      ]),
    );
  }
}

/// An outlet's area: the server's area when it sends one (the area list of outlet creation), else its city.
String? outletArea(Map<String, dynamic> o) {
  final area = o['area'];
  if (area is Map) return asText(area['name']) ?? asText(o['city']);
  return asText(area) ?? asText(o['city']);
}

/// Choose outlets: a search by name, the Area filter (tick one or more areas so the list stays short),
/// and a tick per outlet. Returns the chosen outlet ids.
class ChooseOutletsScreen extends StatefulWidget {
  const ChooseOutletsScreen({super.key, required this.outlets, required this.selected, this.title, this.areas, this.noAreaCount});

  final List<Map<String, dynamic>> outlets;
  final Set<int> selected;

  /// The territory's Area master with how many outlets each has (from the server). Without it, the areas
  /// are worked out from the outlets' cities, as before.
  final List<Map<String, dynamic>>? areas;
  final int? noAreaCount;

  /// The District / Territory, under the title.
  final String? title;

  @override
  State<ChooseOutletsScreen> createState() => _ChooseOutletsScreenState();
}

class _ChooseOutletsScreenState extends State<ChooseOutletsScreen> {
  final _search = TextEditingController();
  late final Set<int> _picked = Set<int>.from(widget.selected);
  final Set<String> _areas = {};
  bool _areaOpen = false;

  bool get _master => (widget.areas ?? const []).isNotEmpty;

  /// What an outlet is filed under: its Area (master) or, without the master, its city.
  String? _areaKey(Map<String, dynamic> o) {
    if (_master) {
      final a = o['area'];
      return a is Map && a['id'] != null ? 'a${a['id']}' : 'none';
    }
    return outletArea(o);
  }

  /// Every area with how many outlets it has, in name order: the territory's own Area master (counts from the
  /// server, an empty one shows 0) and "No area" for outlets without one.
  late final List<({String key, String label, int count})> _areaOpts = _buildAreaOpts();

  List<({String key, String label, int count})> _buildAreaOpts() {
    if (_master) {
      final opts = [
        for (final a in widget.areas!) (key: 'a${a['id']}', label: '${a['name']}', count: (a['count'] as num?)?.toInt() ?? 0),
      ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      final none = widget.noAreaCount ?? widget.outlets.where((o) => _areaKey(o) == 'none').length;
      if (none > 0) opts.add((key: 'none', label: 'No area', count: none));
      return opts;
    }
    final counts = <String, int>{};
    for (final o in widget.outlets) {
      final area = outletArea(o);
      if (area != null) counts[area] = (counts[area] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return [for (final e in sorted) (key: e.key, label: e.key, count: e.value)];
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// What the search and the ticked areas leave.
  List<Map<String, dynamic>> get _shown {
    final needle = _search.text.trim().toLowerCase();
    return [
      for (final o in widget.outlets)
        if ((needle.isEmpty || '${o['name']}'.toLowerCase().contains(needle)) &&
            (_areas.isEmpty || _areas.contains(_areaKey(o))))
          o,
    ];
  }

  void _tick(Map<String, dynamic> o, bool on) {
    final id = o['id'] as int;
    setState(() => on ? _picked.add(id) : _picked.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _shown;
    final ids = [for (final o in rows) o['id'] as int];
    final allShownPicked = ids.isNotEmpty && ids.every(_picked.contains);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Choose outlets', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          if (widget.title != null)
            Text(widget.title!, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
        actions: [
          // Ticks (or clears) what the search and the areas leave on screen.
          TextButton(
            onPressed: ids.isEmpty
                ? null
                : () => setState(() => allShownPicked ? _picked.removeAll(ids) : _picked.addAll(ids)),
            child: Text(allShownPicked ? 'Clear' : 'Select all'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: GradientButton(
            label: 'Done (${_picked.length} selected)',
            onPressed: () => Navigator.pop(context, _picked),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted),
                hintText: 'Search outlet…',
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
          ),
          if (_areaOpts.isNotEmpty) ...[
            const SizedBox(width: 8),
            _areaButton(),
          ],
        ]),
        if (_areaOpen) ...[
          const SizedBox(height: 8),
          _areaList(),
        ],
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No matching outlets', style: TextStyle(color: AppColors.muted))),
          ),
        for (final o in rows) _outletRow(o),
      ]),
    );
  }

  /// "Area ▾", or "Area (2)" while areas are ticked.
  Widget _areaButton() => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _areaOpen = !_areaOpen),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _areas.isEmpty ? Colors.white : AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _areaOpen || _areas.isNotEmpty ? AppColors.warning : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_areas.isEmpty ? 'Area' : 'Area (${_areas.length})',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Color(0xFF1E5BE3))),
            Icon(_areaOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                size: 18, color: const Color(0xFF1E5BE3)),
          ]),
        ),
      );

  /// The areas with a tick and how many outlets each has.
  Widget _areaList() => Material(
        // A Material, not a coloured box: the ticks' ink shows on it.
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 0, 0, 2),
            child: Text('Area', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF1E5BE3))),
          ),
          for (final opt in _areaOpts)
            CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.leading,
              value: _areas.contains(opt.key),
              onChanged: (v) => setState(() => v == true ? _areas.add(opt.key) : _areas.remove(opt.key)),
              title: Text(opt.label,
                  style: TextStyle(fontSize: 13, fontWeight: _areas.contains(opt.key) ? FontWeight.w800 : FontWeight.w500)),
              secondary: Text('${opt.count}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ),
          ]),
        ),
      );

  Widget _outletRow(Map<String, dynamic> o) {
    final masterArea = o['area'] is Map ? asText((o['area'] as Map)['name']) : null;
    final where = asText(o['address']) ?? (_master ? masterArea : outletArea(o));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        value: _picked.contains(o['id']),
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (v) => _tick(o, v == true),
        title: Text('${o['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        subtitle: where == null
            ? null
            : Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}
