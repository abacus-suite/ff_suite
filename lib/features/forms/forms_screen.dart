import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'form_fill_screen.dart';

/// Forms that can be filled at any time (surveys, reports, checklists).
class FormsScreen extends StatefulWidget {
  const FormsScreen({super.key});

  @override
  State<FormsScreen> createState() => _FormsScreenState();
}

class _FormsScreenState extends State<FormsScreen> {
  List<Map<String, dynamic>> _forms = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await Services.api.get('/api/v1/forms', query: {'trigger': 'standalone'}) as List;
      if (mounted) setState(() => (_forms = list.cast<Map<String, dynamic>>(), _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> form) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => FormFillScreen(form: form)));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forms')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ErrorView(message: _error!, onRetry: _load),
            if (!_loading && _error == null && _forms.isEmpty)
              const EmptyView(icon: Icons.assignment_rounded, text: 'No forms to fill right now'),
            for (final form in _forms)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEDE8FF),
                    child: Icon(Icons.assignment_rounded, color: AixoloColors.purple),
                  ),
                  title: Text('${form['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: form['description'] != null ? Text('${form['description']}', maxLines: 2) : null,
                  trailing: form['filled'] == true ? const StatusBadge('filled', label: 'Done today') : const Icon(Icons.chevron_right_rounded),
                  onTap: form['filled'] == true ? null : () => _open(form),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
