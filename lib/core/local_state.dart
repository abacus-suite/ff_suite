import 'api_client.dart';
import 'services.dart';

/// What the phone knows it did while offline.
///
/// Screens read attendance status and the open visit from the server; offline
/// they get the last saved answer. After a queued punch or check-in that
/// answer is out of date, so these helpers rewrite it to match, until the
/// queue syncs and the server's own answer replaces it.
class LocalState {
  static const _status = '/api/v1/attendance/status';
  static const _visit = '/api/v1/visits/current';

  static String _now() => DateTime.now().toUtc().toIso8601String();

  static Future<Map<String, dynamic>> _read(String path) async {
    final cached = await Services.queue.readCache(ApiClient.cacheKey(path, null));
    return (cached?.$1 as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  }

  static Future<void> punched(bool punchIn) async {
    final status = await _read(_status);
    status['punched_in'] = punchIn;
    if (punchIn) {
      status['current'] = {'check_in': _now(), 'offline': true};
    } else {
      status['current'] = null;
    }
    await Services.queue.saveCache(ApiClient.cacheKey(_status, null), status);
  }

  /// A check-in waiting in the queue, shaped like the server's visit.
  static Future<Map<String, dynamic>> visitOpened(Map<String, dynamic> client, String uuid, {String? visitType}) async {
    final visit = <String, dynamic>{
      'id': null,
      'uuid': uuid,
      'client': {'id': client['id'], 'name': client['name']},
      'state': 'ongoing',
      'check_in_at': _now(),
      'visit_type': visitType ?? 'onsite',
      'offline': true,
    };
    await Services.queue.saveCache(ApiClient.cacheKey(_visit, null), visit);
    return visit;
  }

  static Future<void> visitClosed() => Services.queue.saveCache(ApiClient.cacheKey(_visit, null), null);
}
