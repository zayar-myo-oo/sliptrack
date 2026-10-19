import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Vault {
  Vault(List<int> key) : _key = SecretKey(key);
  final SecretKey _key;
  final _cipher = AesGcm.with256bits();
  static Future<Vault> open({bool requireExisting = false}) async {
    const storage = FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
    var key = await storage.read(key: 'sliptrack.database.key.v1');
    if (key == null) {
      if (requireExisting) {
        throw StateError(
          'The database key is unavailable. Restore an encrypted SlipTrack backup.',
        );
      }
      key = base64Encode(
        List.generate(32, (_) => Random.secure().nextInt(256)),
      );
      await storage.write(key: 'sliptrack.database.key.v1', value: key);
    }
    return Vault(base64Decode(key));
  }

  Future<String> seal(Map<String, dynamic> value, String context) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: _key,
      aad: utf8.encode(context),
    );
    return base64Encode(box.concatenation());
  }

  Future<Map<String, dynamic>> unseal(String value, String context) async {
    final bytes = await _cipher.decrypt(
      SecretBox.fromConcatenation(
        base64Decode(value),
        nonceLength: 12,
        macLength: 16,
      ),
      secretKey: _key,
      aad: utf8.encode(context),
    );
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<String> fingerprint(String value) async => base64UrlEncode(
    (await Hmac.sha256().calculateMac(
      utf8.encode(value),
      secretKey: _key,
    )).bytes,
  );
}
