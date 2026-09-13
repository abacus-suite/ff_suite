import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'offline_queue.dart';

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
    _timer ??= Timer.periodic(const Duration(seconds: 45), (_) => flush());
    await refreshCounts();
    unawaited(flush());
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

  Future<SubmitResult> submit(String path, Map<String, dynamic> body, {required String label}) async {
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
    await _store.addRequest(uuid, path, payload, label);
    await refreshCounts();
    return const SubmitResult(null, queued: true);
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
