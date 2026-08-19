import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:southside_music_ui/widgets/netease_image_provider.dart';

const _url = 'https://p1.music.126.net/B-fHwF1m_HHhLSIfSLd-hw==/'
    '109951173218919142.jpg';

void main() {
  testWidgets('NeteaseImageProvider loads netease cover (real net)',
      (tester) async {
    HttpOverrides.global = null;

    await tester.runAsync(() async {
      final provider = NeteaseImageProvider(_url);
      final completer = Completer<ImageInfo>();
      final stream = provider.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info);
        },
        onError: (Object e, StackTrace? s) {
          if (!completer.isCompleted) completer.completeError(e, s);
        },
      );
      stream.addListener(listener);
      try {
        final r = await completer.future.timeout(const Duration(seconds: 20));
        debugPrint('NeteaseImageProvider -> OK '
            '${r.image.width}x${r.image.height}');
      } catch (e) {
        debugPrint('NeteaseImageProvider -> ERROR $e');
        rethrow;
      }
      stream.removeListener(listener);
    });
  });
}
