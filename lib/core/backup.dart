import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class BackupCodec {
  static final _cipher = AesGcm.with256bits();
  static Future<SecretKey> _derive(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  static Future<String> encode(
    Map<String, dynamic> data,
    String password,
  ) async {
    final salt = List.generate(16, (_) => Random.secure().nextInt(256));
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: await _derive(password, salt),
      aad: utf8.encode('SlipTrack:1'),
    );
    return jsonEncode({
      'format': 'SlipTrack',
      'version': 1,
      'salt': base64Encode(salt),
      'data': base64Encode(box.concatenation()),
    });
  }

  static Future<Map<String, dynamic>> decode(
    String text,
    String password,
  ) async {
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['format'] != 'SlipTrack' || j['version'] != 1) {
      throw const FormatException('Unsupported backup');
    }
    final plain = await _cipher.decrypt(
      SecretBox.fromConcatenation(
        base64Decode(j['data']),
        nonceLength: 12,
        macLength: 16,
      ),
      secretKey: await _derive(password, base64Decode(j['salt'])),
      aad: utf8.encode('SlipTrack:1'),
    );
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }
}
