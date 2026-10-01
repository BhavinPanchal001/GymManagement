import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ManagedMediaService {
  static const maxFileBytes = 5 * 1024 * 1024;

  Future<String> savePickedFile(String sourcePath, String category) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException(
        'The selected image is no longer available.',
      );
    }
    if (await source.length() > maxFileBytes) {
      throw const FileSystemException(
        'The selected image is larger than 5 MB.',
      );
    }
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/gym_media');
    await directory.create(recursive: true);
    final extension = _safeExtension(source.uri.pathSegments.last);
    final safeCategory = category.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final destination = File(
      '${directory.path}/${safeCategory}_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    await source.copy(destination.path);
    return destination.path;
  }

  String _safeExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return '';
    final extension = fileName.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension) ? extension : '';
  }
}
