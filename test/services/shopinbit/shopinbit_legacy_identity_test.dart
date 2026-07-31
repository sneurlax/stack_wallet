import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stackwallet/db/drift/shared_db/shared_database.dart';
import 'package:stackwallet/services/shopinbit/shopinbit_service.dart';
import 'package:stackwallet/services/shopinbit/src/client.dart';
import 'package:stackwallet/utilities/flutter_secure_storage_interface.dart';

void main() {
  test('recovers the build 310 customer key and settings', () async {
    final db = SharedDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('''
      CREATE TABLE shopin_bit_settings (
        id INTEGER NOT NULL DEFAULT 0 PRIMARY KEY,
        guidelines_accepted INTEGER NOT NULL DEFAULT 0,
        setup_complete INTEGER NOT NULL DEFAULT 0,
        display_name TEXT
      )
    ''');
    await db.customStatement('''
      INSERT INTO shopin_bit_settings
        (id, guidelines_accepted, setup_complete, display_name)
      VALUES (0, 1, 1, 'Legacy name')
    ''');

    final secureStorage = FakeSecureStorage();
    await secureStorage.write(
      key: kLegacyShopInBitCustomerKeySecureStoreKey,
      value: 'legacy-customer-key',
    );
    final service = ShopInBitService(
      client: ShopInBitClient(accessKey: 'unused', partnerSecret: 'unused'),
      db: db,
      secureStorage: secureStorage,
    );

    expect(await service.ensureCustomerKey(), 'legacy-customer-key');

    final settings = await db.shopInBitSettingsDao.getCurrentSettings();
    expect(settings?.customerKey, 'legacy-customer-key');
    expect(settings?.conciergeGuidelinesAccepted, isTrue);
    expect(settings?.travelGuidelinesAccepted, isTrue);
    expect(settings?.carGuidelinesAccepted, isTrue);
    expect(settings?.setupComplete, isTrue);
    expect(settings?.privacyAccepted, isFalse);
    expect(
      await secureStorage.read(key: kLegacyShopInBitCustomerKeySecureStoreKey),
      isNull,
    );
  });
}
