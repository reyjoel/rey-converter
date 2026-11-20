import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_pdf_converter/main.dart';

void main() {
  const pickerChannel = MethodChannel('plugins.flutter.io/image_picker');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late List<String> imagePaths;
  Object? recovered;
  Future<Object?> Function()? pickImages;
  var pickerCalls = 0;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('rey-preview-test-');
    final bytes = img.encodePng(img.Image(width: 2400, height: 1600));
    imagePaths = [];
    for (var index = 0; index < 5; index++) {
      final file = File('${directory.path}/photo-$index.png');
      await file.writeAsBytes(bytes);
      imagePaths.add(file.path);
    }
  });

  tearDownAll(() => directory.delete(recursive: true));

  setUp(() {
    recovered = null;
    pickImages = null;
    pickerCalls = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pickerChannel, (
      call,
    ) async {
      switch (call.method) {
        case 'retrieve':
          return recovered;
        case 'pickMultiImage':
          pickerCalls++;
          return await pickImages?.call();
        default:
          throw MissingPluginException(call.method);
      }
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pickerChannel,
      null,
    );
    binding.imageCache.clear();
    binding.imageCache.clearLiveImages();
  });

  Future<void> openApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ImageToPdfApp());
    await tester.pumpAndSettle();
  }

  Future<void> verifySmallPreview(WidgetTester tester) async {
    // Alternate real file/codec work with frames to flush FakeAsync callbacks.
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      final previews = tester.widgetList<RawImage>(find.byType(RawImage));
      if (previews.isNotEmpty && previews.first.image != null) break;
    }
    final image = tester.widget<RawImage>(find.byType(RawImage).first).image;
    // Assert actual decoded pixels, not just the thumbnail's layout size.
    expect(image, isNotNull);
    expect(image!.width, lessThanOrEqualTo(128));
    expect(image.height, lessThanOrEqualTo(128));
    expect(image.width / image.height, closeTo(1.5, 0.03));
  }

  testWidgets('five gallery photos use small, undistorted decoded previews', (
    tester,
  ) async {
    pickImages = () async => imagePaths;
    await openApp(tester);
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();

    expect(find.text('Create 5-page PDF'), findsOneWidget);
    await verifySmallPreview(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android startup recovers pending selections', (tester) async {
    recovered = {
      'type': 'image',
      'path': imagePaths.first,
      'pathList': imagePaths,
    };
    await openApp(tester);

    expect(find.text('Create 5-page PDF'), findsOneWidget);
    expect(pickerCalls, 0);
    await verifySmallPreview(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only one picker opens and cancellation re-enables import', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    pickImages = () => pending.future;
    await openApp(tester);
    await tester.tap(find.text('Choose from gallery'));
    await tester.pump();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pump();

    expect(pickerCalls, 1);
    expect(find.text('Opening images…'), findsOneWidget);
    pending.complete(<String>[]);
    await tester.pumpAndSettle();
    expect(find.text('Opening images…'), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
