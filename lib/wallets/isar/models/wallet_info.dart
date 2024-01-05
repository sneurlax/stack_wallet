import 'dart:convert';

import 'package:isar/isar.dart';
import 'package:stackwallet/models/balance.dart';
import 'package:stackwallet/models/isar/models/blockchain_data/address.dart';
import 'package:stackwallet/utilities/enums/coin_enum.dart';
import 'package:stackwallet/wallets/isar/isar_id_interface.dart';
import 'package:stackwallet/wallets/isar/models/wallet_info_meta.dart';
import 'package:uuid/uuid.dart';

part 'wallet_info.g.dart';

@Collection(accessor: "walletInfo", inheritance: false)
class WalletInfo implements IsarId {
  @override
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: false)
  final String walletId;

  String _name;
  String get name => _name;

  @enumerated
  final AddressType mainAddressType;

  /// The highest index [mainAddressType] receiving address of the wallet
  String get cachedReceivingAddress => _cachedReceivingAddress;
  String _cachedReceivingAddress;

  /// Only exposed for Isar. Use the [cachedBalance] getter.
  // Only exposed for isar as Amount cannot be stored in isar easily
  String? get cachedBalanceString => _cachedBalanceString;
  String? _cachedBalanceString;

  /// Only exposed for Isar. Use the [cachedBalanceSecondary] getter.
  // Only exposed for isar as Amount cannot be stored in isar easily
  String? get cachedBalanceSecondaryString => _cachedBalanceSecondaryString;
  String? _cachedBalanceSecondaryString;

  /// Only exposed for Isar. Use the [cachedBalanceTertiary] getter.
  // Only exposed for isar as Amount cannot be stored in isar easily
  String? get cachedBalanceTertiaryString => _cachedBalanceTertiaryString;
  String? _cachedBalanceTertiaryString;

  /// Only exposed for Isar. Use the [coin] getter.
  // Only exposed for isar to avoid dealing with storing enums as Coin can change
  String get coinName => _coinName;
  String _coinName;

  /// User set favourites ordering. No restrictions are placed on uniqueness.
  /// Reordering logic in the ui code should ensure this is unique.
  ///
  /// Also represents if the wallet is a favourite. Any number greater then -1
  /// denotes a favourite. Any number less than 0 means it is not a favourite.
  int get favouriteOrderIndex => _favouriteOrderIndex;
  int _favouriteOrderIndex;

  /// The highest block height the wallet has scanned.
  int get cachedChainHeight => _cachedChainHeight;
  int _cachedChainHeight;

  /// The block at which this wallet was or should be restored from
  int get restoreHeight => _restoreHeight;
  int _restoreHeight;

  // TODO: store these in other data s
  // Should contain specific things based on certain coins only

  // /// Wallet creation chain height. Applies to select coin only.
  // final int creationHeight;

  String? get otherDataJsonString => _otherDataJsonString;
  String? _otherDataJsonString;

  //============================================================================
  //=============== Getters ====================================================

  bool get isFavourite => favouriteOrderIndex > -1;

  List<String> get tokenContractAddresses {
    if (otherData[WalletInfoKeys.tokenContractAddresses] is List) {
      return List<String>.from(
        otherData[WalletInfoKeys.tokenContractAddresses] as List,
      );
    } else {
      return [];
    }
  }

  /// Special case for coins such as firo lelantus
  @ignore
  Balance get cachedBalanceSecondary {
    if (cachedBalanceSecondaryString == null) {
      return Balance.zeroForCoin(coin: coin);
    } else {
      return Balance.fromJson(cachedBalanceSecondaryString!, coin.decimals);
    }
  }

  /// Special case for coins such as firo spark
  @ignore
  Balance get cachedBalanceTertiary {
    if (cachedBalanceTertiaryString == null) {
      return Balance.zeroForCoin(coin: coin);
    } else {
      return Balance.fromJson(cachedBalanceTertiaryString!, coin.decimals);
    }
  }

  @ignore
  Coin get coin => Coin.values.byName(coinName);

  @ignore
  Balance get cachedBalance {
    if (cachedBalanceString == null) {
      return Balance.zeroForCoin(coin: coin);
    } else {
      return Balance.fromJson(cachedBalanceString!, coin.decimals);
    }
  }

  @ignore
  Map<String, dynamic> get otherData => otherDataJsonString == null
      ? {}
      : Map<String, dynamic>.from(jsonDecode(otherDataJsonString!) as Map);

  Future<bool> isMnemonicVerified(Isar isar) async =>
      (await isar.walletInfoMeta.where().walletIdEqualTo(walletId).findFirst())
          ?.isMnemonicVerified ==
      true;

  //============================================================================
  //=============    Updaters   ================================================

  Future<void> updateBalance({
    required Balance newBalance,
    required Isar isar,
  }) async {
    final newEncoded = newBalance.toJsonIgnoreCoin();

    // only update if there were changes to the balance
    if (cachedBalanceString != newEncoded) {
      _cachedBalanceString = newEncoded;

      await isar.writeTxn(() async {
        await isar.walletInfo.deleteByWalletId(walletId);
        await isar.walletInfo.put(this);
      });
    }
  }

  Future<void> updateBalanceSecondary({
    required Balance newBalance,
    required Isar isar,
  }) async {
    final newEncoded = newBalance.toJsonIgnoreCoin();

    // only update if there were changes to the balance
    if (cachedBalanceSecondaryString != newEncoded) {
      _cachedBalanceSecondaryString = newEncoded;

      await isar.writeTxn(() async {
        await isar.walletInfo.deleteByWalletId(walletId);
        await isar.walletInfo.put(this);
      });
    }
  }

  Future<void> updateBalanceTertiary({
    required Balance newBalance,
    required Isar isar,
  }) async {
    final newEncoded = newBalance.toJsonIgnoreCoin();

    // only update if there were changes to the balance
    if (cachedBalanceTertiaryString != newEncoded) {
      _cachedBalanceTertiaryString = newEncoded;

      await isar.writeTxn(() async {
        await isar.walletInfo.deleteByWalletId(walletId);
        await isar.walletInfo.put(this);
      });
    }
  }

  /// copies this with a new chain height and updates the db
  Future<void> updateCachedChainHeight({
    required int newHeight,
    required Isar isar,
  }) async {
    // only update if there were changes to the height
    if (cachedChainHeight != newHeight) {
      _cachedChainHeight = newHeight;
      await isar.writeTxn(() async {
        await isar.walletInfo.deleteByWalletId(walletId);
        await isar.walletInfo.put(this);
      });
    }
  }

  /// update favourite wallet and its index it the ui list.
  /// When [customIndexOverride] is not null the [flag] will be ignored.
  Future<void> updateIsFavourite(
    bool flag, {
    required Isar isar,
    int? customIndexOverride,
  }) async {
    final int index;

    if (customIndexOverride != null) {
      index = customIndexOverride;
    } else if (flag) {
      final highest = await isar.walletInfo
          .where()
          .sortByFavouriteOrderIndexDesc()
          .favouriteOrderIndexProperty()
          .findFirst();
      index = (highest ?? 0) + 1;
    } else {
      index = -1;
    }

    // only update if there were changes to the height
    if (favouriteOrderIndex != index) {
      _favouriteOrderIndex = index;
      await isar.writeTxn(() async {
        await isar.walletInfo.deleteByWalletId(walletId);
        await isar.walletInfo.put(this);
      });
    }
  }

  /// copies this with a new name and updates the db
  Future<void> updateName({
    required String newName,
    required Isar isar,
  }) async {
    // don't allow empty names
    if (newName.isEmpty) {
      throw Exception("Empty wallet name not allowed!");
    }

    // only update if there were changes to the name
    if (name != newName) {
      _name = newName;
      await isar.writeTxn(() async {
        await isar.walletInfo.deleteByWalletId(walletId);
        await isar.walletInfo.put(this);
      });
    }
  }

  /// copies this with a new name and updates the db
  Future<void> updateReceivingAddress({
    required String newAddress,
    required Isar isar,
  }) async {
    // only update if there were changes to the name
    if (cachedReceivingAddress != newAddress) {
      _cachedReceivingAddress = newAddress;
      await isar.writeTxn(() async {
        await isar.walletInfo.deleteByWalletId(walletId);
        await isar.walletInfo.put(this);
      });
    }
  }

  /// update [otherData] with the map entries in [newEntries]
  Future<void> updateOtherData({
    required Map<String, dynamic> newEntries,
    required Isar isar,
  }) async {
    final Map<String, dynamic> newMap = {};
    newMap.addAll(otherData);
    newMap.addAll(newEntries);
    final encodedNew = jsonEncode(newMap);

    // only update if there were changes
    if (_otherDataJsonString != encodedNew) {
      _otherDataJsonString = encodedNew;
      await isar.writeTxn(() async {
        await isar.walletInfo.deleteByWalletId(walletId);
        await isar.walletInfo.put(this);
      });
    }
  }

  /// copies this with a new name and updates the db
  Future<void> setMnemonicVerified({
    required Isar isar,
  }) async {
    final meta =
        await isar.walletInfoMeta.where().walletIdEqualTo(walletId).findFirst();
    if (meta == null) {
      await isar.writeTxn(() async {
        await isar.walletInfoMeta.deleteByWalletId(walletId);
        await isar.walletInfoMeta.put(
          WalletInfoMeta(
            walletId: walletId,
            isMnemonicVerified: true,
          ),
        );
      });
    } else if (meta.isMnemonicVerified == false) {
      await isar.writeTxn(() async {
        await isar.walletInfoMeta.put(
          WalletInfoMeta(
            walletId: walletId,
            isMnemonicVerified: true,
          ),
        );
      });
    } else {
      throw Exception(
        "setMnemonicVerified() called on already"
        " verified wallet: $name, $walletId",
      );
    }
  }

  //============================================================================

  WalletInfo({
    required String coinName,
    required this.walletId,
    required String name,
    required this.mainAddressType,

    // cachedReceivingAddress should never actually be empty in practice as
    // on wallet init it will be set
    String cachedReceivingAddress = "",
    int favouriteOrderIndex = -1,
    int cachedChainHeight = 0,
    int restoreHeight = 0,
    bool isMnemonicVerified = false,
    String? cachedBalanceString,
    String? cachedBalanceSecondaryString,
    String? cachedBalanceTertiaryString,
    String? otherDataJsonString,
  })  : assert(
          Coin.values.map((e) => e.name).contains(coinName),
        ),
        _coinName = coinName,
        _name = name,
        _cachedReceivingAddress = cachedReceivingAddress,
        _favouriteOrderIndex = favouriteOrderIndex,
        _cachedChainHeight = cachedChainHeight,
        _restoreHeight = restoreHeight,
        _cachedBalanceString = cachedBalanceString,
        _cachedBalanceSecondaryString = cachedBalanceSecondaryString,
        _cachedBalanceTertiaryString = cachedBalanceTertiaryString,
        _otherDataJsonString = otherDataJsonString;

  static WalletInfo createNew({
    required Coin coin,
    required String name,
    int restoreHeight = 0,
    String? walletIdOverride,
    String? otherDataJsonString,
  }) {
    return WalletInfo(
      coinName: coin.name,
      walletId: walletIdOverride ?? const Uuid().v1(),
      name: name,
      mainAddressType: coin.primaryAddressType,
      restoreHeight: restoreHeight,
      otherDataJsonString: otherDataJsonString,
    );
  }

  @Deprecated("Legacy support")
  factory WalletInfo.fromJson(
    Map<String, dynamic> jsonObject,
    AddressType mainAddressType,
  ) {
    final coin = Coin.values.byName(jsonObject["coin"] as String);
    return WalletInfo(
      coinName: coin.name,
      walletId: jsonObject["id"] as String,
      name: jsonObject["name"] as String,
      mainAddressType: mainAddressType,
    );
  }

  @Deprecated("Legacy support")
  Map<String, String> toMap() {
    return {
      "name": name,
      "id": walletId,
      "coin": coin.name,
    };
  }

  @Deprecated("Legacy support")
  String toJsonString() {
    return jsonEncode(toMap());
  }

  @override
  String toString() {
    return "WalletInfo: ${toJsonString()}";
  }
}

abstract class WalletInfoKeys {
  static const String tokenContractAddresses = "tokenContractAddressesKey";
  static const String epiccashData = "epiccashDataKey";
  static const String bananoMonkeyImageBytes = "monkeyImageBytesKey";
  static const String tezosDerivationPath = "tezosDerivationPathKey";
}
