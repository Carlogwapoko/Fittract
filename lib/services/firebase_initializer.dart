import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

Future<FirebaseApp>? _initialization;

Future<FirebaseApp> ensureFirebaseInitialized() {
  if (Firebase.apps.isNotEmpty) return Future.value(Firebase.apps.first);
  final pending = _initialization;
  if (pending != null) return pending;

  late final Future<FirebaseApp> initialization;
  initialization =
      Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).catchError((Object error, StackTrace stackTrace) {
        if (identical(_initialization, initialization)) _initialization = null;
        Error.throwWithStackTrace(error, stackTrace);
      });
  _initialization = initialization;
  return initialization;
}
