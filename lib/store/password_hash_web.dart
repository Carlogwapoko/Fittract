import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

extension type _Pbkdf2Params._(JSObject _) implements JSObject {
  external factory _Pbkdf2Params({
    required String name,
    required String hash,
    required JSUint8Array salt,
    required int iterations,
  });
}

Future<Uint8List?> derivePbkdf2({
  required String password,
  required List<int> salt,
  required int iterations,
  required int keyLength,
}) async {
  if (!web.window.isSecureContext) return null;

  final cryptoKey = await web.window.crypto.subtle
      .importKey(
        'raw',
        utf8.encode(password).toJS,
        'PBKDF2'.toJS,
        false,
        ['deriveBits'.toJS].toJS,
      )
      .toDart;
  final params = _Pbkdf2Params(
    name: 'PBKDF2',
    hash: 'SHA-256',
    salt: Uint8List.fromList(salt).toJS,
    iterations: iterations,
  );
  final bits = await web.window.crypto.subtle
      .deriveBits(params, cryptoKey, keyLength * 8)
      .toDart;
  return Uint8List.view(bits.toDart);
}
