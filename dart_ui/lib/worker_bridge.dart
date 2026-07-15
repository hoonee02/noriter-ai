import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Request/response bridge to the Web Worker running worker_main.dart
/// (compiled separately -- see build.sh). Correlates replies to calls via
/// an incrementing id since postMessage is a bare event, not a Future.
class WorkerBridge {
  WorkerBridge._(this._worker);

  final web.Worker _worker;
  int _nextId = 1;
  final _pending = <int, Completer<Map<String, dynamic>>>{};

  static WorkerBridge start() {
    final worker = web.Worker(
      'worker_bootstrap.js'.toJS,
      web.WorkerOptions(type: 'module'),
    );
    late final WorkerBridge bridge;
    void onMessage(web.MessageEvent e) {
      final data = (e.data.dartify() as Map).cast<String, dynamic>();
      final id = (data['id'] as num).toInt();
      final result = (data['result'] as Map).cast<String, dynamic>();
      bridge._pending.remove(id)?.complete(result);
    }

    worker.onmessage = onMessage.toJS;
    bridge = WorkerBridge._(worker);
    return bridge;
  }

  Future<Map<String, dynamic>> call(String type, Map<String, dynamic> payload) {
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _worker.postMessage({'id': id, 'type': type, 'payload': payload}.jsify());
    return completer.future;
  }
}
