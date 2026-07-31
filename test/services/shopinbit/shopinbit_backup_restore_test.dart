import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stackwallet/db/drift/shared_db/shared_database.dart';
import 'package:stackwallet/pages/settings_views/global_settings_view/stack_backup_views/helpers/shopinbit_backup.dart';
import 'package:stackwallet/services/shopinbit/shopinbit_service.dart';
import 'package:stackwallet/services/shopinbit/src/client.dart';
import 'package:stackwallet/utilities/flutter_secure_storage_interface.dart';

void main() {
  test('restores a legacy key without restoring cached tickets', () async {
    final db = SharedDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = ShopInBitService(
      client: ShopInBitClient(accessKey: 'unused', partnerSecret: 'unused'),
      db: db,
      secureStorage: FakeSecureStorage(),
    );

    await restoreShopInBitBackup({
      'shopinBit': {
        'shopinBitCustomerKey': 'legacy-key',
        'shopinBitOrders': [
          {
            'ticketId': 'SIB-42',
            'category': 1,
            'status': 2,
            'requestDescription': 'Find a train ticket',
            'deliveryCountry': 'DE',
            'messages': const <Map<String, dynamic>>[],
            'createdAt': '2026-01-01T00:00:00.000Z',
            'apiTicketId': 42,
          },
        ],
      },
    }, service);

    expect(
      (await db.shopInBitSettingsDao.getCurrentSettings())?.customerKey,
      'legacy-key',
    );
    expect(await db.select(db.shopInBitTickets).get(), isEmpty);
  });

  test('keeps the newest key active when restoring a current backup', () async {
    final db = SharedDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = ShopInBitService(
      client: ShopInBitClient(accessKey: 'unused', partnerSecret: 'unused'),
      db: db,
      secureStorage: FakeSecureStorage(),
    );

    await restoreShopInBitBackup({
      'shopinBit': {
        'shopinBitCustomerKeys': ['newest', 'older'],
      },
    }, service);

    expect(
      (await db.shopInBitSettingsDao.getCurrentSettings())?.customerKey,
      'newest',
    );
    expect(
      await db.shopInBitSettingsDao.watchAll().first.then(
        (settings) => settings.map((setting) => setting.customerKey).toList(),
      ),
      ['newest', 'older'],
    );
  });
}
