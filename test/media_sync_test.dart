import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/utils/image_storage_utils.dart';
import 'package:gym/widgets/customer_avatar.dart';
import 'package:gym/widgets/gym_logo_widget.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDirectory;
  late Uint8List sourceBytes;

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp('gym_media_test_');
    final source = img.Image(width: 1200, height: 600);
    img.fill(source, color: img.ColorRgb8(25, 100, 175));
    sourceBytes = img.encodePng(source);
  });

  tearDown(() async {
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  test(
    'customer thumbnail fields serialize safely for old and new records',
    () {
      final customer = Customer(
        id: 'member-1',
        name: 'Test Member',
        phone: '123',
        imagePath: '/documents/media/avatar_member-1.jpg',
        imageBase64: 'thumbnail-data',
        joinDate: DateTime(2026),
      );

      final restored = Customer.fromMap(customer.toMap());
      expect(restored.imageBase64, 'thumbnail-data');
      expect(restored.copyWith(clearImageBase64: true).imageBase64, isNull);

      final legacy = Customer.fromMap({
        'id': 'legacy',
        'name': 'Legacy Member',
        'phone': '456',
        'joinDate': '2026-01-01T00:00:00.000',
      });
      expect(legacy.imageBase64, isNull);
    },
  );

  test(
    'gym logo thumbnail fields serialize safely for old and new records',
    () {
      const settings = GymSettings(
        gymLogoPath: '/documents/media/gym_logo.jpg',
        gymLogoBase64: 'thumbnail-data',
      );

      final restored = GymSettings.fromMap(settings.toMap());
      expect(restored.gymLogoBase64, 'thumbnail-data');
      expect(restored.copyWith(clearGymLogoBase64: true).gymLogoBase64, isNull);
      expect(GymSettings.fromMap(const {}).gymLogoBase64, isNull);
    },
  );

  test(
    'persistent images are JPEG-compressed within the local size limit',
    () async {
      final source = File('${testDirectory.path}/temporary.png');
      await source.writeAsBytes(sourceBytes);

      final savedPath = await ImageStorageUtils.persistImage(
        source.path,
        'avatar member/1.png',
        documentsDirectory: testDirectory,
      );
      final saved = File(savedPath);
      final decoded = img.decodeImage(await saved.readAsBytes());

      expect(savedPath, '${testDirectory.path}/media/avatar_member_1.jpg');
      expect(await saved.exists(), isTrue);
      expect(decoded, isNotNull);
      expect(decoded!.width, 800);
      expect(decoded.height, 400);
    },
  );

  test('synced thumbnails are square JPEG images', () {
    final base64Thumbnail = ImageStorageUtils.createThumbnailBase64FromBytes(
      sourceBytes,
    );
    final decodedBytes = ImageStorageUtils.decodeBase64Image(base64Thumbnail);
    final decodedImage = img.decodeImage(decodedBytes!);

    expect(decodedImage, isNotNull);
    expect(decodedImage!.width, ImageStorageUtils.thumbnailDimension);
    expect(decodedImage.height, ImageStorageUtils.thumbnailDimension);
    expect(ImageStorageUtils.decodeBase64Image('bm90IGFuIGltYWdl'), isNull);
  });

  testWidgets('customer avatar falls back to synced thumbnail', (tester) async {
    final thumbnail = ImageStorageUtils.createThumbnailBase64FromBytes(
      sourceBytes,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerAvatar(
            imagePath: '${testDirectory.path}/missing.jpg',
            imageBase64: thumbnail,
            name: 'Test Member',
          ),
        ),
      ),
    );

    final memoryDecoration = find.byWidgetPredicate((widget) {
      if (widget is! Container || widget.decoration is! BoxDecoration) {
        return false;
      }
      final decoration = widget.decoration as BoxDecoration;
      return decoration.image?.image is MemoryImage;
    });
    expect(memoryDecoration, findsOneWidget);
    expect(find.text('TM'), findsNothing);
  });

  testWidgets('gym logo falls back to synced thumbnail', (tester) async {
    final thumbnail = ImageStorageUtils.createThumbnailBase64FromBytes(
      sourceBytes,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GymLogoWidget(
            logoPath: '${testDirectory.path}/missing.jpg',
            logoBase64: thumbnail,
            gymName: 'Test Gym',
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.fitness_center_rounded), findsNothing);
  });
}
