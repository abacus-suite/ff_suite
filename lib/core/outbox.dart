import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'offline_queue.dart';
import 'services.dart';
import 'warm_up.dart';

class SubmitResult {
  const SubmitResult(this.data, {this.queued = false});

  /// The server's answer; null when the action was queued.
  final dynamic data;

  /// True when there was no network: it is saved on the phone and will be sent.
  final bool queued;

  Map<String, dynamic> get map => (data as Map?)?.cast<String, dynamic>() ?? const {};
}

/// Actions that must not be lost to a dead zone.
///
/// [submit] sends straight away when it can; without network it saves the
/// request with the moment it happened and a uuid, and [flush] sends the
/// queue later, oldest first, so the server sees check-in before demand before
/// check-out. A request the server refuses stays visible with its reason.
class Outbox {
  Outbox(this._api, this._store);

  final ApiClient _api;
  final OfflineQueue _store;

  /// Waiting to be sent.
  final ValueNotifier<int> pending = ValueNotifier(0);

  /// Refused by the server; needs the person to retry or discard.
  final ValueNotifier<int> failed = ValueNotifier(0);

  Timer? _timer;
  Future<void>? _flushing;

  Future<void> start() async {
    _timer ??= Timer.periodic(const Duration(seconds: 45), (_) async {
      await flush();
      // Keep the offline copy fresh while there is network (at most every 30 min).
      if (_api.online.value) unawaited(WarmUp.run());
    });
    await refreshCounts();
    unawaited(flush().then((_) => WarmUp.run(force: true)));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refreshCounts() async {
    final all = await _store.requests();
    failed.value = all.where((r) => r.error != null).length;
    pending.value = all.length - failed.value;
  }

  /// What a queued request is called in the Sync list when the screen did not say.
  static String describe(String path) {
    const names = <String, String>{
      '/api/v1/attendance/punch-in': 'Punch in',
      '/api/v1/attendance/punch-out': 'Punch out',
      '/api/v1/attendance/regularisations': 'Attendance correction',
      '/api/v1/visits/check-in': 'Check in',
      '/api/v1/visits/check-out': 'Check out',
      '/api/v1/orders': 'Order',
      '/api/v1/collections': 'Payment',
      '/api/v1/deposits': 'Deposit to office',
      '/api/v1/expenses': 'Expense claim',
      '/api/v1/clients': 'New customer',
      '/api/v1/leaves': 'Leave request',
      '/api/v1/route-plan/days': 'Route plan',
      '/api/v1/stock/counts': 'Stock count',
      '/api/v1/tasks': 'New task',
    };
    if (names.containsKey(path)) return names[path]!;
    if (path.contains('/steps/')) return 'Visit step';
    if (path.contains('/responses')) return 'Form';
    if (path.contains('/approvals/')) return path.endsWith('approve') ? 'Approval' : 'Rejection';
    if (path.startsWith('/api/v1/tasks/')) return path.endsWith('/done') ? 'Finish task' : 'Start task';
    if (path.startsWith('/api/v1/deposits/')) return 'Deposit decision';
    if (path.startsWith('/api/v1/leaves/')) return 'Withdraw leave';
    if (path.startsWith('/api/v1/allowances/')) return 'Submit allowance';
    return 'Change';
  }

  Future<SubmitResult> submit(String path, Map<String, dynamic> body, {String? label}) async {
    final payload = Map<String, dynamic>.of(body);
    final uuid = (payload['uuid'] as String?) ?? const Uuid().v4();
    payload['uuid'] = uuid;
    // Nothing may overtake older queued work: send that first.
    if (pending.value > 0) await flush();
    if (pending.value == 0) {
      try {
        return SubmitResult(await _api.post(path, payload));
      } on ApiException catch (e) {
        if (e.code != 'network') rethrow;
      }
    }
    payload['at'] = DateTime.now().toUtc().toIso8601String();
    await _store.addRequest(uuid, path, payload, label ?? describe(path));
    await refreshCounts();
    _tellQueued(label ?? describe(path));
    return const SubmitResult(null, queued: true);
  }

  /// One message for every screen: shown just after the screen's own, so it is the one that stays.
  void _tellQueued(String label) {
    Future.delayed(const Duration(milliseconds: 350), () {
      final context = Services.navigatorKey.currentContext;
      if (context == null) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('$label saved on the phone · it will sync when you are back online'),
          backgroundColor: const Color(0xFFB45309),
        ));
    });
  }

  /// Send what is waiting. Safe to call often; concurrent calls share one run.
  Future<void> flush() => _flushing ??= _run().whenComplete(() => _flushing = null);

  Future<void> _run() async {
    final queue = await _store.requests();
    for (final request in queue) {
      if (request.error != null) continue;
      try {
        await _api.post(request.path, request.body);
        await _store.removeRequest(request.uuid);
      } on ApiException catch (e) {
        if (e.code == 'network') break;
        await _store.markRequest(request.uuid, e.message);
      }
    }
    await refreshCounts();
  }

  Future<List<QueuedRequest>> list() => _store.requests();

  Future<void> retry(String uuid) async {
    await _store.markRequest(uuid, null);
    await refreshCounts();
    await flush();
  }

  Future<void> discard(String uuid) async {
    await _store.removeRequest(uuid);
    await refreshCounts();
  }
}
