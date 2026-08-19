import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// dart:io 的 [HttpClientRequest.headers.add] 会向已存在的 `User-Agent` 追加,
/// 导致请求头同时携带默认 `Dart/x (dart:io)` 与浏览器 UA,被网易云 CDN 拒绝(403)。
/// 这里用 [HttpHeaders.set] 覆盖默认 UA,保证请求表现为浏览器。
const Map<String, String> neteaseImageHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
};

/// 网易云图片专用 [ImageProvider]:使用 dart:io 手动下载字节并解码,
/// 通过 [HttpHeaders.set] 正确覆盖 User-Agent,避免 `Image.network` 内部
/// `headers.add` 导致双 UA 返回 403 的问题。
class NeteaseImageProvider extends ImageProvider<NeteaseImageProvider> {
  final String url;
  final double scale;

  const NeteaseImageProvider(this.url, {this.scale = 1.0});

  @override
  Future<NeteaseImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<NeteaseImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    NeteaseImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: key.url,
    );
  }

  Future<ui.Codec> _loadAsync(
    NeteaseImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(key.url));
      neteaseImageHeaders.forEach((name, value) {
        // set 覆盖默认 UA,而非 add 追加。
        request.headers.set(name, value);
      });
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Image load failed (${response.statusCode})',
          uri: Uri.parse(key.url),
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      final Uint8List bytes = builder.takeBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final codec = await decode(buffer);
      return codec;
    } finally {
      client.close(force: true);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is NeteaseImageProvider && other.url == url && other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'NeteaseImageProvider')}("$url", scale: $scale)';
}
