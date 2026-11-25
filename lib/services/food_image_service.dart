import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

abstract interface class FoodImageUploader {
  Future<String> upload({
    required String uid,
    required Uint8List bytes,
    required String fileName,
  });

  Future<Uint8List?> download({required String uid, required String imageId});
}

class FoodImageService implements FoodImageUploader {
  static const _maxImageBytes = 680 * 1024;

  @override
  Future<String> upload({
    required String uid,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not initialized.');
    }
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError(
        'The signed-in account does not match the active account.',
      );
    }
    if (bytes.isEmpty || bytes.length > _maxImageBytes) {
      throw StateError('Choose an image smaller than 680 KB to sync.');
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
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('foodImages')
        .doc();
    await ref.set({
      'imageData': base64Encode(bytes),
      'contentType': contentType,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    return ref.id;
  }

  @override
  Future<Uint8List?> download({
    required String uid,
    required String imageId,
  }) async {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not initialized.');
    }
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError(
        'The signed-in account does not match the active account.',
      );
    }
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('foodImages')
        .doc(imageId)
        .get();
    final encoded = snapshot.data()?['imageData'];
    if (encoded is! String || encoded.isEmpty) return null;
    return Uint8List.fromList(base64Decode(encoded));
  }
}
