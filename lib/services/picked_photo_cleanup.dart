import 'picked_photo_cleanup_stub.dart'
    if (dart.library.io) 'picked_photo_cleanup_io.dart' as cleanup;

Future<void> deletePickedPhoto(String path) => cleanup.deletePickedPhoto(path);
