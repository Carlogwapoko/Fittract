import 'dart:io';

Future<void> deletePickedPhoto(String path) => File(path).delete();
