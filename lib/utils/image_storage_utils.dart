import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ImageStorageUtils {
  static const int maxImageDimension = 800;
  static const int thumbnailDimension = 100;

  static Future<String> persistImage(
    String sourcePath,
    String fileName, {
    Directory? documentsDirectory,
  }) async {
    final source = File(normalizeFilePath(sourcePath));
    if (!await source.exists()) {
      throw StateError('Selected image is no longer available.');
    }

    final decoded = img.decodeImage(await source.readAsBytes());
    if (decoded == null) {
      throw StateError('Selected image format is not supported.');
    }

    final oriented = img.bakeOrientation(decoded);
    final resized = _resizeWithin(oriented, maxImageDimension);
    final encoded = img.encodeJpg(resized, quality: 82);
    final root = documentsDirectory ?? await getApplicationDocumentsDirectory();
    final mediaDirectory = Directory('${root.path}/media');
    if (!await mediaDirectory.exists()) {
      await mediaDirectory.create(recursive: true);
    }

    final safeName = _jpegFileName(fileName);
    final target = File('${mediaDirectory.path}/$safeName');
    await target.writeAsBytes(encoded, flush: true);
    return target.path;
  }

  static Future<String?> createThumbnailBase64(String filePath) async {
    final file = File(normalizeFilePath(filePath));
    if (!await file.exists()) return null;
    return createThumbnailBase64FromBytes(await file.readAsBytes());
  }

  static String? createThumbnailBase64FromBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    final thumbnail = img.copyResizeCropSquare(
      oriented,
      size: thumbnailDimension,
      interpolation: img.Interpolation.average,
    );
    return base64Encode(img.encodeJpg(thumbnail, quality: 72));
  }

  static Uint8List? decodeBase64Image(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final bytes = base64Decode(value);
      return img.decodeImage(bytes) == null ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> loadImageBytes(
    String? filePath,
    String? base64Value,
  ) async {
    if (filePath != null &&
        filePath.isNotEmpty &&
        !filePath.startsWith('avatar:') &&
        !filePath.startsWith('http://') &&
        !filePath.startsWith('https://')) {
      final file = File(normalizeFilePath(filePath));
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) return bytes;
      }
    }
    return decodeBase64Image(base64Value);
  }

  static Future<void> deleteManagedImage(String? filePath) async {
    if (filePath == null ||
        filePath.isEmpty ||
        filePath.startsWith('avatar:') ||
        filePath.startsWith('http://') ||
        filePath.startsWith('https://')) {
      return;
    }

    final root = await getApplicationDocumentsDirectory();
    final mediaPrefix = '${Directory('${root.path}/media').absolute.path}/';
    final file = File(normalizeFilePath(filePath)).absolute;
    if (!file.path.startsWith(mediaPrefix) || !await file.exists()) return;
    await file.delete();
  }

  static String normalizeFilePath(String rawPath) {
    if (!rawPath.startsWith('file://')) return rawPath;
    try {
      return Uri.parse(rawPath).toFilePath();
    } catch (_) {
      return rawPath.replaceFirst('file://', '');
    }
  }

  static img.Image _resizeWithin(img.Image source, int maxDimension) {
    if (source.width <= maxDimension && source.height <= maxDimension) {
      return source;
    }
    if (source.width >= source.height) {
      return img.copyResize(
        source,
        width: maxDimension,
        interpolation: img.Interpolation.average,
      );
    }
    return img.copyResize(
      source,
      height: maxDimension,
      interpolation: img.Interpolation.average,
    );
  }

  static String _jpegFileName(String fileName) {
    final sanitized = fileName
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceFirst(RegExp(r'\.[^.]+$'), '');
    final baseName = sanitized.isEmpty ? 'image' : sanitized;
    return '$baseName.jpg';
  }
}
