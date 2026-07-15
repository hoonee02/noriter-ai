import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Thin JS-interop wrapper over `window.__TAURI__` (enabled via
/// `withGlobalTauri: true` in tauri.conf.json). No dart:io -- this is the
/// only way the Wasm UI talks to the Rust backend.
@JS('window.__TAURI__.core.invoke')
external JSPromise<JSAny?> _invoke(JSString cmd, JSAny? args);

@JS('window.__TAURI__.event.listen')
external JSPromise<JSFunction> _listen(
  JSString event,
  JSFunction handler,
);

@JS('window.__TAURI__')
external JSAny? get _tauriGlobal;

/// True only inside the actual Tauri webview. Outside it (e.g. testing the
/// wasm build in a plain browser) `window.__TAURI__` is never injected.
bool get isAvailable => _tauriGlobal != null;

/// Invokes a Tauri command. Return value is whatever the Rust command
/// returns, dartified (String, num, bool, Map, List, or null).
Future<dynamic> invoke(String cmd, [Map<String, dynamic>? args]) async {
  if (!isAvailable) return null;
  final jsArgs = args == null ? null : args.jsify();
  final result = await _invoke(cmd.toJS, jsArgs).toDart;
  return result?.dartify();
}

/// Subscribes to a Tauri backend event (e.g. "telegram-event"). Returns an
/// unlisten callback. No-ops outside the Tauri webview.
Future<void Function()> listen(
  String event,
  void Function(Map<String, dynamic> payload) onEvent,
) async {
  if (!isAvailable) return () {};
  final handler = ((JSAny? e) {
    final map = e.dartify() as Map;
    final payload = (map['payload'] as Map).cast<String, dynamic>();
    onEvent(payload);
  }).toJS;

  final unlisten = await _listen(event.toJS, handler).toDart;
  return () => unlisten.callAsFunction();
}
