import 'package:flutter/services.dart';

class OcrBlock {
  OcrBlock(this.text, this.box, this.confidence);
  final String text;

  /// Normalized [left, top, width, height], with a top-left origin on both OSes.
  final List<double> box;
  final double? confidence;
}

class OcrResult {
  OcrResult({
    required this.text,
    required this.hash,
    required this.blocks,
    this.confidence,
    this.supportedLanguages = const [],
    this.language,
  });
  final String text, hash;
  final List<OcrBlock> blocks;
  final double? confidence;
  final List<String> supportedLanguages;
  // Script detection over recognized output; never claimed as recognition support.
  final String? language;
}

abstract interface class OCRService {
  Future<OcrResult> recognizeText(String source);
}

class OnDeviceOCR implements OCRService {
  static const channel = MethodChannel('app.sliptrack/media');
  @override
  Future<OcrResult> recognizeText(String source) async {
    final j = Map<String, dynamic>.from(
      await channel.invokeMethod('ocr', {'id': source}),
    );
    final text = j['text'] as String;
    return OcrResult(
      text: text,
      hash: j['hash'],
      confidence: (j['confidence'] as num?)?.toDouble(),
      language: detectLanguage(text),
      supportedLanguages: List<String>.from(j['languages'] ?? []),
      blocks: (j['blocks'] as List? ?? [])
          .map(
            (b) => OcrBlock(
              b['text'],
              (b['box'] as List).map((n) => (n as num).toDouble()).toList(),
              (b['confidence'] as num?)?.toDouble(),
            ),
          )
          .toList(),
    );
  }

  static String? detectLanguage(String text) =>
      RegExp(r'[\u1000-\u109f]').hasMatch(text)
      ? 'my'
      : RegExp(r'[\u0e00-\u0e7f]').hasMatch(text)
      ? 'th'
      : RegExp(r'[a-zA-Z]').hasMatch(text)
      ? 'en'
      : null;
}

abstract interface class GalleryService {
  Future<List<String>> incoming();
  Future<String> permission({bool request = false});
  Future<List<String>> pick();
  Future<List<String>> assets({
    required int afterMs,
    required int sinceMs,
    required int offset,
  });
  Future<Uint8List?> thumbnail(String id);
  Future<void> automatic(bool enabled);
  Stream<void> get changes;
}

class NativeGallery implements GalleryService {
  String? albumId;
  Future<List<Map<String, dynamic>>> albums() async =>
      (await channel.invokeListMethod('albums') ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  static const channel = OnDeviceOCR.channel;
  static const events = EventChannel('app.sliptrack/media_changes');
  @override
  Future<List<String>> incoming() async =>
      List<String>.from(await channel.invokeMethod('incoming') ?? []);
  @override
  Stream<void> get changes => events.receiveBroadcastStream().map((_) {});
  @override
  Future<String> permission({bool request = false}) async =>
      await channel.invokeMethod<String>('permission', {'request': request}) ??
      'denied';
  @override
  Future<List<String>> pick() async =>
      List<String>.from(await channel.invokeMethod('pick') ?? []);

  /// Takes one photo with the camera; returns an in-memory source id.
  Future<List<String>> camera() async =>
      List<String>.from(await channel.invokeMethod('camera') ?? []);
  @override
  Future<List<String>> assets({
    required int afterMs,
    required int sinceMs,
    required int offset,
  }) async => List<String>.from(
    await channel.invokeMethod('assets', {
          'albumId': albumId,
          'afterMs': afterMs,
          'sinceMs': sinceMs,
          'offset': offset,
        }) ??
        [],
  );
  @override
  Future<Uint8List?> thumbnail(String id) =>
      channel.invokeMethod<Uint8List>('thumbnail', {'id': id});
  @override
  Future<void> automatic(bool enabled) =>
      channel.invokeMethod('automatic', {'enabled': enabled});
}
