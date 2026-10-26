import 'dart:async';

import 'package:flutter/foundation.dart';

import 'format.dart';
import 'services.dart';

/// Loads the working day onto the phone while there is network, so a dead
/// zone later still has customers, products, today's route and the forms to
/// work with - not only the screens that happened to be opened.
class WarmUp {
  static DateTime? _last;
  static Future<void>? _running;

  /// Last time the phone was filled.
  static final ValueNotifier<DateTime?> lastDone = ValueNotifier(null);

  /// Refill if the saved copy is older than [maxAge] (or on [force]).
  static Future<void> run({bool force = false, Duration maxAge = const Duration(minutes: 30)}) {
    if (!force && _last != null && DateTime.now().difference(_last!) < maxAge) return Future.value();
    return _running ??= runZoned(_fill, zoneValues: {#ffBackground: true}).whenComplete(() => _running = null);
  }

  // Background filling goes two at a time, so the screens the user opens are
  // never stuck behind a wall of warm-up requests on the server.
  static const _parallel = 2;
  static int _active = 0;
  static final List<Completer<void>> _waiting = [];

  static Future<dynamic> _get(String path, [Map<String, dynamic>? query]) async {
    while (_active >= _parallel) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _active++;
    try {
      // Let whatever the user just opened go first.
      while (Services.api.busy > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      return await Services.api.get(path, query: query);
    } catch (_) {
      return null;
    } finally {
      _active--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  static Future<void> _fill() async {
    // Not while the app is opening: the first screen gets the server to itself.
    await Future<void>.delayed(const Duration(seconds: 20));
    final profile = Services.auth.profile;
    if (profile == null) return;
    final today = fmtDate(DateTime.now());

    // The screens themselves, with the same filters they ask for.
    final lists = await Future.wait<dynamic>([
      _get('/api/v1/attendance/status'),
      _get('/api/v1/visits/current'),
      _get('/api/v1/clients', {'limit': 100}),
      if (profile.feature('routes')) _get('/api/v1/beat/today', {'date': today}) else Future.value(null),
      if (profile.feature('routes')) _get('/api/v1/beat/today') else Future.value(null),
      if (profile.feature('orders')) _get('/api/v1/products', {'limit': 300}) else Future.value(null),
      if (profile.feature('orders')) _get('/api/v1/products/categories') else Future.value(null),
      _get('/api/v1/contact-categories'),
      _get('/api/v1/expense-categories'),
      if (profile.feature('orders')) _get('/api/v1/foc/schemes') else Future.value(null),
      if (profile.paymentCollection) _get('/api/v1/collection-modes') else Future.value(null),
      _get('/api/v1/leaves'),
      _get('/api/v1/tasks', {'state': 'todo,in_progress'}),
      _get('/api/v1/tasks', {'scope': 'mine', 'state': 'todo,in_progress'}),
      _get('/api/v1/targets'),
      _get('/api/v1/visits'),
      _get('/api/v1/tracking/my-day'),
      if (profile.feature('forms')) _get('/api/v1/forms', {'trigger': 'standalone'}) else Future.value(null),
    ]);
    if (!Services.api.online.value) return;

    // Every customer on today's route and the nearest list: their page and what
    // a visit there needs (outcomes, forms, last stock count).
    final ids = <int>{};
    for (final answer in [lists[2], lists[3]]) {
      final clients = (answer is Map ? answer['clients'] as List? : null) ?? const [];
      for (final client in clients) {
        final id = (client as Map)['id'];
        if (id is int) ids.add(id);
      }
    }
    final perClient = ids.take(80).toList();
    for (var i = 0; i < perClient.length; i += 6) {
      if (!Services.api.online.value) return;
      await Future.wait([
        for (final id in perClient.skip(i).take(6)) ...[
          _get('/api/v1/clients/$id'),
          _get('/api/v1/clients/$id/balance'),
          if (profile.feature('visits')) _get('/api/v1/visit-outcomes', {'partner_id': id}),
          if (profile.stockCount) _get('/api/v1/stock/last', {'partner_id': id}),
          if (profile.visitSteps) _get('/api/v1/visits/0/steps', {'partner_id': id}),
          if (profile.feature('forms')) _get('/api/v1/forms', {'trigger': 'visit', 'partner_id': id}),
        ],
      ]);
    }
    _last = DateTime.now();
    lastDone.value = _last;
  }
}
