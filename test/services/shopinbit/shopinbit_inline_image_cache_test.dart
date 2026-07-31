import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stackwallet/services/shopinbit/src/models/message.dart';

void main() {
  test('oversized inline images are decoded but never cached', () {
    final cache = InlineImageCache(maxBytes: 4);
    final source = _dataImage([1, 2, 3, 4, 5]);

    final first = cache.decode(source);
    final second = cache.decode(source);

    expect(first, [1, 2, 3, 4, 5]);
    expect(identical(first, second), isFalse);
    expect(cache.cachedBytes, 0);
  });

  test('inline image cache reuses entries within its byte cap', () {
    final cache = InlineImageCache(maxBytes: 4);
    final source = _dataImage([1, 2, 3, 4]);

    final first = cache.decode(source);
    final second = cache.decode(source);

    expect(identical(first, second), isTrue);
    expect(cache.cachedBytes, 4);
  });
}

String _dataImage(List<int> bytes) =>
    'data:image/png;base64,${base64Encode(bytes)}';
