import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FoodImageService {
  Future<String> upload({
    required String uid,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not initialized.');
    }
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('The signed-in account does not match the active account.');
    }
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw StateError('Choose an image smaller than 10 MB.');
    }

    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : 'jpg';
    final safeExtension = switch (extension) {
      'jpg' || 'jpeg' => 'jpg',
      'png' => 'png',
      'webp' => 'webp',
      'gif' => 'gif',
      'heic' => 'heic',
      _ => 'jpg',
    };
    final contentType = switch (safeExtension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'heic' => 'image/heic',
      _ => 'image/jpeg',
    };
    final ref = FirebaseStorage.instance
        .ref()
        .child(
          'users/$uid/foods/${DateTime.now().microsecondsSinceEpoch}.$safeExtension',
        );
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }
}
