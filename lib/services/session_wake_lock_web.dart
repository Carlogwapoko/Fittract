import 'dart:js_interop';

import 'package:web/web.dart' as web;

class SessionWakeLock {
  web.WakeLockSentinel? _sentinel;

  Future<void> enable() async {
    try {
      _sentinel = await web.window.navigator.wakeLock.request('screen').toDart;
    } catch (error) {
      if (error.isA<web.DOMException>()) return;
      rethrow;
    }
  }

  Future<void> disable() async {
    final sentinel = _sentinel;
    _sentinel = null;
    if (sentinel == null || sentinel.released) return;
    try {
      await sentinel.release().toDart;
    } catch (error) {
      if (error.isA<web.DOMException>()) return;
      rethrow;
    }
  }
}
