import '../../../../../services/shopinbit/shopinbit_service.dart';

/// Restores only the customer identity needed to recover tickets from the
/// ShopInBit API. Ticket rows in historical backups are intentionally ignored.
Future<void> restoreShopInBitBackup(
  Map<String, dynamic> backup,
  ShopInBitService service,
) async {
  final rawSection = backup['shopinBit'];
  if (rawSection is! Map) return;

  final newestFirst = <String>[];
  final rawKeys = rawSection['shopinBitCustomerKeys'];
  if (rawKeys is List) {
    for (final rawKey in rawKeys) {
      if (rawKey is! String) continue;
      final key = rawKey.trim();
      if (key.isNotEmpty && !newestFirst.contains(key)) {
        newestFirst.add(key);
      }
    }
  }

  final rawLegacyKey = rawSection['shopinBitCustomerKey'];
  final legacyKey = rawLegacyKey is String ? rawLegacyKey.trim() : '';
  final restoreOrder = newestFirst.isNotEmpty
      ? newestFirst.reversed.toList(growable: false)
      : <String>[if (legacyKey.isNotEmpty) legacyKey];
  if (restoreOrder.isEmpty) return;

  await service.db.transaction(() async {
    final restoreStart = DateTime.now().subtract(
      Duration(seconds: restoreOrder.length),
    );
    for (var i = 0; i < restoreOrder.length; i++) {
      await service.recoverCustomerKey(
        restoreOrder[i],
        lastUsedAt: restoreStart.add(Duration(seconds: i + 1)),
      );
    }
  });
}
