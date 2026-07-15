import 'dart:js_interop';

import 'worker/logic.dart' as logic;

extension type _MessageEvent(JSObject _) implements JSObject {
  external JSAny? get data;
}

@JS('self.postMessage')
external void _postMessage(JSAny message);

@JS('self.onmessage')
external set _onMessage(JSFunction f);

void main() {
  void onMessage(_MessageEvent event) {
    final message = (event.data.dartify() as Map).cast<String, dynamic>();
    final id = message['id'];
    final type = message['type'] as String;
    final payload = (message['payload'] as Map?)?.cast<String, dynamic>() ?? const {};

    final result = logic.handle(type, payload);
    _postMessage({'id': id, 'result': result}.jsify()!);
  }

  _onMessage = onMessage.toJS;
}
