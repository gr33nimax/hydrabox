import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:meow_client/data/subscription/happ_crypt5_local.dart';
import 'package:meow_client/data/subscription/happ_crypto_link.dart';

const _legacyBazaruCrypt5Link =
    'happ://crypt5/rwlbVfsFNh3DkZMG6l21KayyuN6w8s++eme3mY/GujURFRyotW+bOtt3U1KYSBLEr8fcmQGMU8KkaygYMozvBW8NfeNNaYKdyziHXt+zaJfNk3wZPTxbFjt2CgaXP0qvnv7pN4tJr2tjfOpOhuobTe7pfSHi8XM/p7QZDhQsokzh85Nf5JNXoUyH4QlU/JLhjARsvJaeBIiczsvY83Xra0TupO8C4J0w9wItjD9o==qwLpeWtbYbKiz1kWVhvTbgC37Rl/U6JAKUe1btfAbPvk+0Q9MBncO7ZVbYVIonI26iCPoO+8rliOO7SGrEE8glMszYSZfg0WbLgylZhbiKw/oEw8mjDWmqRL947dbgw7ZhP/deTGLnbX++IhHOBj+ddV2nobxBh8ImoHBtBmOtrzMChfPYBwZIylcRumxlQQiHgEcwyu+5Q19j7JNOraYPHoi7X1Mk0RTb64OoiwP0hGCM2LS3CN9IDk7hZ7VtCBtO8FLh5TvoEoYn+HWuDE6CFM3YgOCPLUkrlcW+JXBYuHEAi6hCJNUmo4IwTADRmZYL1btfZvHvW1wOMdGx2SwlwwgTW0gtAsUBzUxYvi622XfHamt2Pmqo3CzBqaIaMEpmV9k5e1TAl9KLMpyp+Qgmj5aJt1zdess7/AGoz/cCAiWnXwnQ27js6rOVf/wRoOfjzZixBGbN9PkIBb5AXPaELxS87e1QnALJPFbFDFJ/rYutsK6NizTrNLE81kTH72UL3mDvwUCfwGX+PqFVjQttI/1db+Tn5eupBTtg63DooDSoePyRsyFq5G7zE6LLaYBZA4unyrLpUkbboZt9b/WPUL5Il/hoCk3Y3NHQOokRUxYkJ9tTjydDy3e0BVgvozcS+WOMrUABTq+WbE2YU3VUj4ZsicjYSa4Y1pfS9wcIE=bxhgfd';

const _legacyVipCrypt5Link =
    'happ://crypt5/rwlbvcel5ygYEIGL8j18LXR9ciC/KWAvquDsXc70T2zhF1eg8LoJHQF1r5jglJdlDOadfF7hvA7234wCQBBHh8jZKqDfbcDkekU0eOXAJBtlQZ0/AIf9QmJtm2DQncnuwwmFHHKQMvq1o7RnXI8+bmO75HRFHh2HUOHvTuB+IXmmeLrSpxfUTpJOtZ4EYFdLwlQ6pzzu4IMb0=yGo0m06lAPXcwaQdB9XYwUdaF5cS/IWYO6jTThYXgBS1oPd+97MMfJRqj4IjwzZQPn/UQFdxvQlXMrc3+7xARp/uwOkA5t6BMgUF9ELHz1jhGSvfQNtfuIOKcBHT5t4hHjIMufz0eT4u0Ihez8eoMZ/SaruxMoUd/cR173KqFShs3u49qwHYTpOK4EQqUjOpM2CMmbEZTAK4WFvzkAYcu7eM1QYriwqnb1RNempYCG8Ww2JoXE6WAOPlkO8MoyJtAkaL7EDfYoGn78CQf3cbwKRTZ7l/0g4P4vx95OelsoRBCgEv5f5sPt8fgN0uht2ZGbtoKkZTlOsIpTUMAsNemt3H8jUOX3xU2m0AKFvakogIFiZRmwy1v22AR7eW51/Hu6ZOcITMaJBKTLfxcO/SF5iLfiVMJOf7fVq9FrSgKPWIhO01AlQQattbVrYbhRGhE4lOCrUcE6bHmxZSVNPyN35qZEm+nzAqm0Ycf2XgAr1su9o/NswP1EdP7pgjtTUMqAPB4cA9qnthWGjpLvOULBd96eZv8SyAfpmA7b+FghL7+Ita0gMlAk1FvGHVg9ArPkKRavEZxWNuK9n2fayAUB+QwNjBPxQVkcO9BzSWE0Luq9w6C6FugIr8RLcyzCefH8CLNROG/566kSS5iuNCkl5RCHKxCggCK84fHg54Bxs=FChgfd';

bool get _runHappCryptoAssetTests =>
    Platform.environment['HAPP_CRYPTO_TESTS'] == 'true';

bool _skipWhenHappCryptoAssetsAreUnavailable() {
  if (!_runHappCryptoAssetTests) {
    markTestSkipped(
      'Happ crypto asset tests require HAPP_CRYPTO_TESTS=true and '
      'private assets restored into assets/happ_crypto.',
    );
    return true;
  }
  return false;
}

void main() {
  test('crypt5 capability requires every compatibility asset', () async {
    final support = await HappCrypt5Local.checkSupport(
      bundle: _MemoryAssetBundle({
        'assets/happ_crypto/selectors.json': '[["ab", "cdef", "gh"]]',
        'assets/happ_crypto/expanded_rsa_keys.json': '{"abcdefgh":"key"}',
      }),
    );

    expect(support.supported, isFalse);
  });

  test('crypt5 capability accepts a complete structural asset set', () async {
    final support = await HappCrypt5Local.checkSupport(
      bundle: _MemoryAssetBundle({
        'assets/happ_crypto/selectors.json': '[["ab", "cdef", "gh"]]',
        'assets/happ_crypto/expanded_rsa_keys.json': '{"abcdefgh":"key1"}',
        'assets/happ_crypto/crypt51_rsa_keys.json': '{"abcdefgh":"key2"}',
        'assets/happ_crypto/native_rsa_keys.json': '{"abcdefgh":"key3"}',
      }),
    );

    expect(support.supported, isTrue);
  });

  test('happRequestInfo enables HWID and Happ user agent', () {
    final info = HappCryptoLinkDecoder.happRequestInfo();

    expect(info.happCryptoLink, isNull);
    expect(info.customUserAgent, happLatestUserAgent);
    expect(info.requireHwid, isTrue);
  });

  test('happRequestInfo preserves happ crypto source when provided', () {
    final info = HappCryptoLinkDecoder.happRequestInfo(
      happCryptoLink: 'happ://crypt5/example',
    );

    expect(info.happCryptoLink, 'happ://crypt5/example');
    expect(info.customUserAgent, happLatestUserAgent);
    expect(info.requireHwid, isTrue);
  });

  test('crypt5 local decoder handles sampled corpora when present', () async {
    if (_skipWhenHappCryptoAssetsAreUnavailable()) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    final files = [
      File('/home/ddosxd/code/all-happ-keys/unique_links.txt'),
      File(
        '/home/ddosxd/code/all-happ-keys/unique_links_2_crypt51_pr_fast.txt',
      ),
    ];

    for (final file in files) {
      if (!file.existsSync()) continue;
      final link = file
          .readAsLinesSync()
          .map((line) => line.trim())
          .firstWhere((line) => line.startsWith('happ://crypt5/'));

      final result = await HappCryptoLinkDecoder.decrypt(link);
      expect(result, startsWith('http'));
    }
  });

  test('crypt5 local decoder handles legacy marker links', () async {
    if (_skipWhenHappCryptoAssetsAreUnavailable()) return;
    TestWidgetsFlutterBinding.ensureInitialized();

    expect(
      await HappCryptoLinkDecoder.decrypt(_legacyBazaruCrypt5Link),
      'https://raw.githubusercontent.com/elenavatrunkina-Testhub/B-a-Z-a-R-u-V_P_N/refs/heads/main/BaZaRu%20VPN.txt',
    );
    expect(
      await HappCryptoLinkDecoder.decrypt(_legacyVipCrypt5Link),
      'https://raw.githubusercontent.com/elenavatrunkina-Testhub/B-c-v-i-p/refs/heads/main/VipBC.txt',
    );
  });

  test('crypt5 legacy keyset includes sampled marker families', () {
    if (_skipWhenHappCryptoAssetsAreUnavailable()) return;
    final keyset =
        (jsonDecode(
                  File(
                    'assets/happ_crypto/expanded_rsa_keys.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>)
            .keys
            .toSet();

    expect(
      keyset,
      containsAll({
        'axrtpjmw',
        'iiiaoadi',
        'irnejvft',
        'kafnafqo',
        'lbrwfdhg',
        'odxznmtg',
        'qahftrxc',
        'ypmtavce',
      }),
    );
  });
}

class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    final value = assets[key];
    if (value == null) {
      throw StateError('Missing test asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }
}
