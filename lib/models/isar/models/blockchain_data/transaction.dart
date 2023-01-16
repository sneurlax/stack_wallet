import 'dart:math';

import 'package:isar/isar.dart';
import 'package:stackwallet/models/isar/models/address/address.dart';
import 'package:stackwallet/models/isar/models/blockchain_data/input.dart';
import 'package:stackwallet/models/isar/models/blockchain_data/output.dart';

part 'transaction.g.dart';

@Collection()
class Transaction {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String txid;

  @Index()
  late int timestamp;

  @enumerated
  late TransactionType type;

  @enumerated
  late TransactionSubType subType;

  late int amount;

  // TODO: do we need this?
  // late List<dynamic> aliens;

  late int fee;

  late int? height;

  late bool isCancelled;

  late bool? isLelantus;

  late String? slateId;

  late String? otherData;

  @Backlink(to: "transaction")
  final address = IsarLink<Address>();

  final inputs = IsarLinks<Input>();

  final outputs = IsarLinks<Output>();

  int getConfirmations(int currentChainHeight) {
    if (height == null || height! <= 0) return 0;
    return max(0, currentChainHeight - (height! - 1));
  }

  bool isConfirmed(int currentChainHeight, int minimumConfirms) {
    final confirmations = getConfirmations(currentChainHeight);
    return confirmations >= minimumConfirms;
  }
}

// Used in Isar db and stored there as int indexes so adding/removing values
// in this definition should be done extremely carefully in production
enum TransactionType {
  // TODO: add more types before prod release?
  outgoing,
  incoming,
  sentToSelf, // should we keep this?
  unknown;
}

// Used in Isar db and stored there as int indexes so adding/removing values
// in this definition should be done extremely carefully in production
enum TransactionSubType {
  // TODO: add more types before prod release?
  none,
  bip47Notification, // bip47 payment code notification transaction flag
  mint, // firo specific
  join; // firo specific
}