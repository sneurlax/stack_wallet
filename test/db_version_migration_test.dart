import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:stackwallet/db/drift/shared_db/shared_database.dart';

void main() {
  test('migrates the build 310 shared database from v2 to v3', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'stack-wallet-shared-db-migration-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final databaseFile = File('${tempDir.path}/shared.db');
    final legacy = sqlite.sqlite3.open(databaseFile.path);
    legacy
      ..execute(
        'CREATE TABLE cakepay_orders (order_id TEXT NOT NULL PRIMARY KEY)',
      )
      ..execute('''
        CREATE TABLE shopin_bit_settings (
          id INTEGER NOT NULL DEFAULT 0 PRIMARY KEY,
          guidelines_accepted INTEGER NOT NULL DEFAULT 0,
          setup_complete INTEGER NOT NULL DEFAULT 0,
          display_name TEXT
        )
      ''')
      ..execute('''
        CREATE TABLE shop_in_bit_tickets (
          ticket_id TEXT NOT NULL PRIMARY KEY,
          api_ticket_id INTEGER NOT NULL
        )
      ''')
      ..execute(
        "INSERT INTO shop_in_bit_tickets "
        "(ticket_id, api_ticket_id) VALUES ('legacy-ticket', 42)",
      )
      ..execute('PRAGMA user_version = 2')
      ..dispose();

    final db = SharedDatabase.forTesting(NativeDatabase(databaseFile));
    addTearDown(db.close);

    expect(db.schemaVersion, 3);

    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
        )
        .map((row) => row.read<String>('name'))
        .get();
    expect(tables, contains('shop_in_bit_settings'));
    expect(tables, contains('shop_in_bit_tickets'));
    expect(tables, contains('shop_in_bit_tickets_legacy_v2'));
    expect(tables, contains('app_notifications'));

    final currentTicketColumns = await db
        .customSelect("PRAGMA table_info('shop_in_bit_tickets')")
        .map((row) => row.read<String>('name'))
        .get();
    expect(currentTicketColumns, contains('customer_key'));
    expect(currentTicketColumns, contains('updated_at'));

    final legacyRows = await db
        .customSelect('SELECT * FROM shop_in_bit_tickets_legacy_v2')
        .get();
    expect(legacyRows.single.read<String>('ticket_id'), 'legacy-ticket');

    await db.shopInBitSettingsDao.upsert('customer-key');
    expect(
      (await db.shopInBitSettingsDao.getCurrentSettings())?.customerKey,
      'customer-key',
    );
  });
}
