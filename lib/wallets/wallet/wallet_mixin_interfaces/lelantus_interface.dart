import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:bitcoindart/bitcoindart.dart' as bitcoindart;
import 'package:decimal/decimal.dart';
import 'package:isar/isar.dart';
import 'package:lelantus/lelantus.dart' as lelantus;
import 'package:stackwallet/models/balance.dart';
import 'package:stackwallet/models/isar/models/isar_models.dart';
import 'package:stackwallet/models/lelantus_fee_data.dart';
import 'package:stackwallet/utilities/amount/amount.dart';
import 'package:stackwallet/utilities/enums/derive_path_type_enum.dart';
import 'package:stackwallet/utilities/extensions/impl/uint8_list.dart';
import 'package:stackwallet/utilities/format.dart';
import 'package:stackwallet/utilities/logger.dart';
import 'package:stackwallet/wallets/api/lelantus_ffi_wrapper.dart';
import 'package:stackwallet/wallets/crypto_currency/crypto_currency.dart';
import 'package:stackwallet/wallets/models/tx_data.dart';
import 'package:stackwallet/wallets/wallet/intermediate/bip39_hd_wallet.dart';
import 'package:stackwallet/wallets/wallet/wallet_mixin_interfaces/electrumx_interface.dart';
import 'package:tuple/tuple.dart';

mixin LelantusInterface on Bip39HDWallet, ElectrumXInterface {
  Future<Amount> estimateFeeForLelantus(Amount amount) async {
    final lelantusEntries = await _getLelantusEntry();
    int spendAmount = amount.raw.toInt();
    if (spendAmount == 0 || lelantusEntries.isEmpty) {
      return Amount(
        rawValue: BigInt.from(LelantusFeeData(0, 0, []).fee),
        fractionDigits: cryptoCurrency.fractionDigits,
      );
    }

    final result = await LelantusFfiWrapper.estimateJoinSplitFee(
      spendAmount: amount,
      subtractFeeFromAmount: true,
      lelantusEntries: lelantusEntries,
      isTestNet: cryptoCurrency.network == CryptoCurrencyNetwork.test,
    );

    return Amount(
      rawValue: BigInt.from(result.fee),
      fractionDigits: cryptoCurrency.fractionDigits,
    );
  }

  Future<List<lelantus.DartLelantusEntry>> _getLelantusEntry() async {
    final List<LelantusCoin> lelantusCoins = await mainDB.isar.lelantusCoins
        .where()
        .walletIdEqualTo(walletId)
        .filter()
        .isUsedEqualTo(false)
        .not()
        .group((q) => q
            .valueEqualTo("0")
            .or()
            .anonymitySetIdEqualTo(LelantusFfiWrapper.ANONYMITY_SET_EMPTY_ID))
        .findAll();

    final root = await getRootHDNode();

    final waitLelantusEntries = lelantusCoins.map((coin) async {
      final derivePath = cryptoCurrency.constructDerivePath(
        derivePathType: DerivePathType.bip44,
        chain: LelantusFfiWrapper.MINT_INDEX,
        index: coin.mintIndex,
      );

      try {
        final keyPair = root.derivePath(derivePath);
        final String privateKey = keyPair.privateKey.data.toHex;
        return lelantus.DartLelantusEntry(
          coin.isUsed ? 1 : 0,
          0,
          coin.anonymitySetId,
          int.parse(coin.value),
          coin.mintIndex,
          privateKey,
        );
      } catch (_) {
        Logging.instance.log("error bad key", level: LogLevel.Error);
        return lelantus.DartLelantusEntry(1, 0, 0, 0, 0, '');
      }
    }).toList();

    final lelantusEntries = await Future.wait(waitLelantusEntries);

    if (lelantusEntries.isNotEmpty) {
      // should be redundant as _getUnspentCoins() should
      // already remove all where value=0
      lelantusEntries.removeWhere((element) => element.amount == 0);
    }

    return lelantusEntries;
  }

  Future<TxData> prepareSendLelantus({
    required TxData txData,
  }) async {
    if (txData.recipients!.length != 1) {
      throw Exception(
        "Lelantus send requires a single recipient",
      );
    }

    if (txData.recipients!.first.amount.raw >
        BigInt.from(LelantusFfiWrapper.MINT_LIMIT)) {
      throw Exception(
        "Lelantus sends of more than 5001 are currently disabled",
      );
    }

    try {
      // check for send all
      bool isSendAll = false;
      final balance = info.cachedBalanceSecondary.spendable;
      if (txData.recipients!.first.amount == balance) {
        // print("is send all");
        isSendAll = true;
      }

      final lastUsedIndex =
          await mainDB.getHighestUsedMintIndex(walletId: walletId);
      final nextFreeMintIndex = (lastUsedIndex ?? 0) + 1;

      final root = await getRootHDNode();

      final derivePath = cryptoCurrency.constructDerivePath(
        derivePathType: DerivePathType.bip44,
        chain: 0,
        index: 0,
      );
      final partialDerivationPath = derivePath.substring(
        0,
        derivePath.length - 3,
      );

      final result = await LelantusFfiWrapper.createJoinSplitTransaction(
        txData: txData,
        subtractFeeFromAmount: isSendAll,
        nextFreeMintIndex: nextFreeMintIndex,
        locktime: await chainHeight,
        lelantusEntries: await _getLelantusEntry(),
        anonymitySets: await fetchAnonymitySets(),
        cryptoCurrency: cryptoCurrency,
        partialDerivationPath: partialDerivationPath,
        hexRootPrivateKey: root.privateKey.data.toHex,
        chaincode: root.chaincode,
      );

      Logging.instance.log("prepared fee: ${result.fee}", level: LogLevel.Info);
      Logging.instance
          .log("prepared vSize: ${result.vSize}", level: LogLevel.Info);

      // fee should never be less than vSize sanity check
      if (result.fee!.raw.toInt() < result.vSize!) {
        throw Exception(
            "Error in fee calculation: Transaction fee cannot be less than vSize");
      }
      return result;
    } catch (e, s) {
      Logging.instance.log("Exception rethrown in firo prepareSend(): $e\n$s",
          level: LogLevel.Error);
      rethrow;
    }
  }

  Future<TxData> confirmSendLelantus({
    required TxData txData,
  }) async {
    final latestSetId = await electrumXClient.getLelantusLatestCoinId();
    final txid = await electrumXClient.broadcastTransaction(
      rawTx: txData.raw!,
    );

    assert(txid == txData.txid!);

    final lastUsedIndex =
        await mainDB.getHighestUsedMintIndex(walletId: walletId);
    final nextFreeMintIndex = (lastUsedIndex ?? 0) + 1;

    if (txData.spendCoinIndexes != null) {
      // This is a joinsplit

      final spentCoinIndexes = txData.spendCoinIndexes!;
      final List<LelantusCoin> updatedCoins = [];

      // Update all of the coins that have been spent.

      for (final index in spentCoinIndexes) {
        final possibleCoin = await mainDB.isar.lelantusCoins
            .where()
            .mintIndexWalletIdEqualTo(index, walletId)
            .findFirst();

        if (possibleCoin != null) {
          updatedCoins.add(possibleCoin.copyWith(isUsed: true));
        }
      }

      // if a jmint was made add it to the unspent coin index
      final jmint = LelantusCoin(
        walletId: walletId,
        mintIndex: nextFreeMintIndex,
        value: (txData.jMintValue ?? 0).toString(),
        txid: txid,
        anonymitySetId: latestSetId,
        isUsed: false,
        isJMint: true,
        otherData: null,
      );

      try {
        await mainDB.isar.writeTxn(() async {
          for (final c in updatedCoins) {
            await mainDB.isar.lelantusCoins.deleteByMintIndexWalletId(
              c.mintIndex,
              c.walletId,
            );
          }
          await mainDB.isar.lelantusCoins.putAll(updatedCoins);

          await mainDB.isar.lelantusCoins.put(jmint);
        });
      } catch (e, s) {
        Logging.instance.log(
          "$e\n$s",
          level: LogLevel.Fatal,
        );
        rethrow;
      }

      final amount = txData.amount!;

      // add the send transaction
      final transaction = Transaction(
        walletId: walletId,
        txid: txid,
        timestamp: (DateTime.now().millisecondsSinceEpoch ~/ 1000),
        type: TransactionType.outgoing,
        subType: TransactionSubType.join,
        amount: amount.raw.toInt(),
        amountString: amount.toJsonString(),
        fee: txData.fee!.raw.toInt(),
        height: txData.height,
        isCancelled: false,
        isLelantus: true,
        slateId: null,
        nonce: null,
        otherData: null,
        // otherData: transactionInfo["otherData"] as String?,
        inputs: [],
        outputs: [],
        numberOfMessages: null,
      );

      final transactionAddress = await mainDB
              .getAddresses(walletId)
              .filter()
              .valueEqualTo(txData.recipients!.first.address)
              .findFirst() ??
          Address(
            walletId: walletId,
            value: txData.recipients!.first.address,
            derivationIndex: -1,
            derivationPath: null,
            type: AddressType.nonWallet,
            subType: AddressSubType.nonWallet,
            publicKey: [],
          );

      final List<Tuple2<Transaction, Address?>> txnsData = [];

      txnsData.add(Tuple2(transaction, transactionAddress));

      await mainDB.addNewTransactionData(txnsData, walletId);
    } else {
      // This is a mint
      Logging.instance.log("this is a mint", level: LogLevel.Info);

      final List<LelantusCoin> updatedCoins = [];

      for (final mintMap in txData.mintsMapLelantus!) {
        final index = mintMap['index'] as int;
        final mint = LelantusCoin(
          walletId: walletId,
          mintIndex: index,
          value: (mintMap['value'] as int).toString(),
          txid: txid,
          anonymitySetId: latestSetId,
          isUsed: false,
          isJMint: false,
          otherData: null,
        );

        updatedCoins.add(mint);
      }
      // Logging.instance.log(coins);
      try {
        await mainDB.isar.writeTxn(() async {
          await mainDB.isar.lelantusCoins.putAll(updatedCoins);
        });
      } catch (e, s) {
        Logging.instance.log(
          "$e\n$s",
          level: LogLevel.Fatal,
        );
        rethrow;
      }
    }

    return txData.copyWith(
      txid: txid,
    );
  }

  Future<List<Map<String, dynamic>>> fastFetch(List<String> allTxHashes) async {
    List<Map<String, dynamic>> allTransactions = [];

    const futureLimit = 30;
    List<Future<Map<String, dynamic>>> transactionFutures = [];
    int currentFutureCount = 0;
    for (final txHash in allTxHashes) {
      Future<Map<String, dynamic>> transactionFuture =
          electrumXCachedClient.getTransaction(
        txHash: txHash,
        verbose: true,
        coin: cryptoCurrency.coin,
      );
      transactionFutures.add(transactionFuture);
      currentFutureCount++;
      if (currentFutureCount > futureLimit) {
        currentFutureCount = 0;
        await Future.wait(transactionFutures);
        for (final fTx in transactionFutures) {
          final tx = await fTx;
          // delete unused large parts
          tx.remove("hex");
          tx.remove("lelantusData");

          allTransactions.add(tx);
        }
      }
    }
    if (currentFutureCount != 0) {
      currentFutureCount = 0;
      await Future.wait(transactionFutures);
      for (final fTx in transactionFutures) {
        final tx = await fTx;
        // delete unused large parts
        tx.remove("hex");
        tx.remove("lelantusData");

        allTransactions.add(tx);
      }
    }
    return allTransactions;
  }

  Future<Map<Address, Transaction>> getJMintTransactions(
    List<String> transactions,
  ) async {
    try {
      Map<Address, Transaction> txs = {};
      List<Map<String, dynamic>> allTransactions =
          await fastFetch(transactions);

      for (int i = 0; i < allTransactions.length; i++) {
        try {
          final tx = allTransactions[i];

          var sendIndex = 1;
          if (tx["vout"][0]["value"] != null &&
              Decimal.parse(tx["vout"][0]["value"].toString()) > Decimal.zero) {
            sendIndex = 0;
          }
          tx["amount"] = tx["vout"][sendIndex]["value"];
          tx["address"] = tx["vout"][sendIndex]["scriptPubKey"]["addresses"][0];
          tx["fees"] = tx["vin"][0]["nFees"];

          final Amount amount = Amount.fromDecimal(
            Decimal.parse(tx["amount"].toString()),
            fractionDigits: cryptoCurrency.fractionDigits,
          );

          final txn = Transaction(
            walletId: walletId,
            txid: tx["txid"] as String,
            timestamp: tx["time"] as int? ??
                (DateTime.now().millisecondsSinceEpoch ~/ 1000),
            type: TransactionType.outgoing,
            subType: TransactionSubType.join,
            amount: amount.raw.toInt(),
            amountString: amount.toJsonString(),
            fee: Amount.fromDecimal(
              Decimal.parse(tx["fees"].toString()),
              fractionDigits: cryptoCurrency.fractionDigits,
            ).raw.toInt(),
            height: tx["height"] as int?,
            isCancelled: false,
            isLelantus: true,
            slateId: null,
            otherData: null,
            nonce: null,
            inputs: [],
            outputs: [],
            numberOfMessages: null,
          );

          final address = await mainDB
                  .getAddresses(walletId)
                  .filter()
                  .valueEqualTo(tx["address"] as String)
                  .findFirst() ??
              Address(
                walletId: walletId,
                value: tx["address"] as String,
                derivationIndex: -2,
                derivationPath: null,
                type: AddressType.nonWallet,
                subType: AddressSubType.unknown,
                publicKey: [],
              );

          txs[address] = txn;
        } catch (e, s) {
          Logging.instance.log(
              "Exception caught in getJMintTransactions(): $e\n$s",
              level: LogLevel.Info);
          rethrow;
        }
      }
      return txs;
    } catch (e, s) {
      Logging.instance.log(
          "Exception rethrown in getJMintTransactions(): $e\n$s",
          level: LogLevel.Info);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchAnonymitySets() async {
    try {
      final latestSetId = await electrumXClient.getLelantusLatestCoinId();

      final List<Map<String, dynamic>> sets = [];
      List<Future<Map<String, dynamic>>> anonFutures = [];
      for (int i = 1; i <= latestSetId; i++) {
        final set = electrumXCachedClient.getAnonymitySet(
          groupId: "$i",
          coin: info.coin,
        );
        anonFutures.add(set);
      }
      await Future.wait(anonFutures);
      for (int i = 1; i <= latestSetId; i++) {
        Map<String, dynamic> set = (await anonFutures[i - 1]);
        set["setId"] = i;
        sets.add(set);
      }
      return sets;
    } catch (e, s) {
      Logging.instance.log(
          "Exception rethrown from refreshAnonymitySets: $e\n$s",
          level: LogLevel.Error);
      rethrow;
    }
  }

  Future<Map<int, dynamic>> getSetDataMap(int latestSetId) async {
    final Map<int, dynamic> setDataMap = {};
    final anonymitySets = await fetchAnonymitySets();
    for (int setId = 1; setId <= latestSetId; setId++) {
      final setData = anonymitySets
          .firstWhere((element) => element["setId"] == setId, orElse: () => {});

      if (setData.isNotEmpty) {
        setDataMap[setId] = setData;
      }
    }
    return setDataMap;
  }

  // TODO: verify this function does what we think it does
  Future<void> refreshLelantusData() async {
    final lelantusCoins = await mainDB.isar.lelantusCoins
        .where()
        .walletIdEqualTo(walletId)
        .filter()
        .isUsedEqualTo(false)
        .not()
        .valueEqualTo(0.toString())
        .findAll();

    final List<LelantusCoin> updatedCoins = [];

    final usedSerialNumbersSet =
        (await electrumXCachedClient.getUsedCoinSerials(
      coin: info.coin,
    ))
            .toSet();

    final root = await getRootHDNode();

    for (final coin in lelantusCoins) {
      final _derivePath = cryptoCurrency.constructDerivePath(
        derivePathType: DerivePathType.bip44,
        chain: LelantusFfiWrapper.MINT_INDEX,
        index: coin.mintIndex,
      );

      final mintKeyPair = root.derivePath(_derivePath);

      final String serialNumber = lelantus.GetSerialNumber(
        int.parse(coin.value),
        mintKeyPair.privateKey.data.toHex,
        coin.mintIndex,
        isTestnet: cryptoCurrency.network == CryptoCurrencyNetwork.test,
      );
      final bool isUsed = usedSerialNumbersSet.contains(serialNumber);

      if (isUsed) {
        updatedCoins.add(coin.copyWith(isUsed: isUsed));
      }

      final tx = await mainDB.getTransaction(walletId, coin.txid);
      if (tx == null) {
        Logging.instance.log(
          "Transaction with txid=${coin.txid} not found in local db!",
          level: LogLevel.Error,
        );
      }
    }

    if (updatedCoins.isNotEmpty) {
      try {
        await mainDB.isar.writeTxn(() async {
          for (final c in updatedCoins) {
            await mainDB.isar.lelantusCoins.deleteByMintIndexWalletId(
              c.mintIndex,
              c.walletId,
            );
          }
          await mainDB.isar.lelantusCoins.putAll(updatedCoins);
        });
      } catch (e, s) {
        Logging.instance.log(
          "$e\n$s",
          level: LogLevel.Fatal,
        );
        rethrow;
      }
    }
  }

  /// Should only be called within the standard wallet [recover] function due to
  /// mutex locking. Otherwise behaviour MAY be undefined.
  Future<void> recoverLelantusWallet({
    required int latestSetId,
    required Map<dynamic, dynamic> setDataMap,
    required Set<String> usedSerialNumbers,
  }) async {
    final root = await getRootHDNode();

    final derivePath = cryptoCurrency.constructDerivePath(
      derivePathType: DerivePathType.bip44,
      chain: 0,
      index: 0,
    );

    // get "m/$purpose'/$coinType'/$account'/" from "m/$purpose'/$coinType'/$account'/0/0"
    final partialDerivationPath = derivePath.substring(
      0,
      derivePath.length - 3,
    );

    final result = await LelantusFfiWrapper.restore(
      hexRootPrivateKey: root.privateKey.data.toHex,
      chaincode: root.chaincode,
      cryptoCurrency: cryptoCurrency,
      latestSetId: latestSetId,
      setDataMap: setDataMap,
      usedSerialNumbers: usedSerialNumbers,
      walletId: walletId,
      partialDerivationPath: partialDerivationPath,
    );

    final currentHeight = await chainHeight;

    final txns = await mainDB
        .getTransactions(walletId)
        .filter()
        .isLelantusIsNull()
        .or()
        .isLelantusEqualTo(false)
        .findAll();

    // Edit the receive transactions with the mint fees.
    List<Transaction> editedTransactions = [];

    for (final coin in result.lelantusCoins) {
      String txid = coin.txid;
      Transaction? tx;
      try {
        tx = txns.firstWhere((e) => e.txid == txid);
      } catch (_) {
        tx = null;
      }

      if (tx == null || tx.subType == TransactionSubType.join) {
        // This is a jmint.
        continue;
      }

      List<Transaction> inputTxns = [];
      for (final input in tx.inputs) {
        Transaction? inputTx;
        try {
          inputTx = txns.firstWhere((e) => e.txid == input.txid);
        } catch (_) {
          inputTx = null;
        }
        if (inputTx != null) {
          inputTxns.add(inputTx);
        }
      }
      if (inputTxns.isEmpty) {
        //some error.
        Logging.instance.log(
          "cryptic \"//some error\" occurred in staticProcessRestore on lelantus coin: $coin",
          level: LogLevel.Error,
        );
        continue;
      }

      int mintFee = tx.fee;
      int sharedFee = mintFee ~/ inputTxns.length;
      for (final inputTx in inputTxns) {
        final edited = Transaction(
          walletId: inputTx.walletId,
          txid: inputTx.txid,
          timestamp: inputTx.timestamp,
          type: inputTx.type,
          subType: TransactionSubType.mint,
          amount: inputTx.amount,
          amountString: Amount(
            rawValue: BigInt.from(inputTx.amount),
            fractionDigits: cryptoCurrency.fractionDigits,
          ).toJsonString(),
          fee: sharedFee,
          height: inputTx.height,
          isCancelled: false,
          isLelantus: true,
          slateId: null,
          otherData: txid,
          nonce: null,
          inputs: inputTx.inputs,
          outputs: inputTx.outputs,
          numberOfMessages: null,
        )..address.value = inputTx.address.value;
        editedTransactions.add(edited);
      }
    }
    // Logging.instance.log(editedTransactions, addToDebugMessagesDB: false);

    Map<String, Transaction> transactionMap = {};
    for (final e in txns) {
      transactionMap[e.txid] = e;
    }
    // Logging.instance.log(transactionMap, addToDebugMessagesDB: false);

    // update with edited transactions
    for (final tx in editedTransactions) {
      transactionMap[tx.txid] = tx;
    }

    transactionMap.removeWhere((key, value) =>
        result.lelantusCoins.any((element) => element.txid == key) ||
        ((value.height == -1 || value.height == null) &&
            !value.isConfirmed(currentHeight, cryptoCurrency.minConfirms)));

    try {
      await mainDB.isar.writeTxn(() async {
        await mainDB.isar.lelantusCoins.putAll(result.lelantusCoins);
      });
    } catch (e, s) {
      Logging.instance.log(
        "$e\n$s",
        level: LogLevel.Fatal,
      );
      // don't just rethrow since isar likes to strip stack traces for some reason
      throw Exception("e=$e & s=$s");
    }

    Map<String, Tuple2<Address?, Transaction>> data = {};

    for (final entry in transactionMap.entries) {
      data[entry.key] = Tuple2(entry.value.address.value, entry.value);
    }

    // Create the joinsplit transactions.
    final spendTxs = await getJMintTransactions(
      result.spendTxIds,
    );
    Logging.instance.log(spendTxs, level: LogLevel.Info);

    for (var element in spendTxs.entries) {
      final address = element.value.address.value ??
          data[element.value.txid]?.item1 ??
          element.key;
      // Address(
      //   walletId: walletId,
      //   value: transactionInfo["address"] as String,
      //   derivationIndex: -1,
      //   type: AddressType.nonWallet,
      //   subType: AddressSubType.nonWallet,
      //   publicKey: [],
      // );

      data[element.value.txid] = Tuple2(address, element.value);
    }

    final List<Tuple2<Transaction, Address?>> txnsData = [];

    for (final value in data.values) {
      final transactionAddress = value.item1!;
      final outs =
          value.item2.outputs.where((_) => true).toList(growable: false);
      final ins = value.item2.inputs.where((_) => true).toList(growable: false);

      txnsData.add(Tuple2(
          value.item2.copyWith(inputs: ins, outputs: outs).item1,
          transactionAddress));
    }

    await mainDB.addNewTransactionData(txnsData, walletId);
  }

  /// Builds and signs a transaction
  Future<TxData> buildMintTransaction({required TxData txData}) async {
    final signingData = await fetchBuildTxData(txData.utxos!.toList());

    final txb = bitcoindart.TransactionBuilder(
      network: bitcoindart.NetworkType(
        messagePrefix: cryptoCurrency.networkParams.messagePrefix,
        bech32: cryptoCurrency.networkParams.bech32Hrp,
        bip32: bitcoindart.Bip32Type(
          public: cryptoCurrency.networkParams.pubHDPrefix,
          private: cryptoCurrency.networkParams.privHDPrefix,
        ),
        pubKeyHash: cryptoCurrency.networkParams.p2pkhPrefix,
        scriptHash: cryptoCurrency.networkParams.p2shPrefix,
        wif: cryptoCurrency.networkParams.wifPrefix,
      ),
    );
    txb.setVersion(2);

    final int height = await chainHeight;

    txb.setLockTime(height);
    int amount = 0;
    // Add transaction inputs
    for (var i = 0; i < signingData.length; i++) {
      txb.addInput(
        signingData[i].utxo.txid,
        signingData[i].utxo.vout,
        null,
        signingData[i].output,
      );
      amount += signingData[i].utxo.value;
    }

    for (var mintsElement in txData.mintsMapLelantus!) {
      Logging.instance.log("using $mintsElement", level: LogLevel.Info);
      Uint8List mintu8 =
          Format.stringToUint8List(mintsElement['script'] as String);
      txb.addOutput(mintu8, mintsElement['value'] as int);
    }

    for (var i = 0; i < signingData.length; i++) {
      txb.sign(
        vin: i,
        keyPair: signingData[i].keyPair!,
        witnessValue: signingData[i].utxo.value,
      );
    }
    var incomplete = txb.buildIncomplete();
    var txId = incomplete.getId();
    var txHex = incomplete.toHex();
    int fee = amount - incomplete.outs[0].value!;

    var builtHex = txb.build();

    return txData.copyWith(
      recipients: [
        (
          amount: Amount(
            rawValue: BigInt.from(incomplete.outs[0].value!),
            fractionDigits: cryptoCurrency.fractionDigits,
          ),
          address: "no address for lelantus mints",
          isChange: false,
        )
      ],
      vSize: builtHex.virtualSize(),
      txid: txId,
      raw: txHex,
      height: height,
      txType: TransactionType.outgoing,
      txSubType: TransactionSubType.mint,
      fee: Amount(
        rawValue: BigInt.from(fee),
        fractionDigits: cryptoCurrency.fractionDigits,
      ),
    );

    // return {
    //   "transaction": builtHex,
    //   "txid": txId,
    //   "txHex": txHex,
    //   "value": amount - fee,
    //   "fees": Amount(
    //     rawValue: BigInt.from(fee),
    //     fractionDigits: coin.decimals,
    //   ).decimal.toDouble(),
    //   "height": height,
    //   "txType": "Sent",
    //   "confirmed_status": false,
    //   "amount": Amount(
    //     rawValue: BigInt.from(amount),
    //     fractionDigits: coin.decimals,
    //   ).decimal.toDouble(),
    //   "timestamp": DateTime.now().millisecondsSinceEpoch ~/ 1000,
    //   "subType": "mint",
    //   "mintsMap": mintsMap,
    // };
  }

  /// Returns the mint transaction hex to mint all of the available funds.
  Future<TxData> _mintSelection() async {
    final currentChainHeight = await chainHeight;
    final List<UTXO> availableOutputs = await mainDB
        .getUTXOs(walletId)
        .filter()
        .isBlockedEqualTo(false)
        .findAll();
    final List<UTXO?> spendableOutputs = [];

    // Build list of spendable outputs and totaling their satoshi amount
    for (var i = 0; i < availableOutputs.length; i++) {
      if (availableOutputs[i].isConfirmed(
                  currentChainHeight, cryptoCurrency.minConfirms) ==
              true &&
          !(availableOutputs[i].isCoinbase &&
              availableOutputs[i].getConfirmations(currentChainHeight) <=
                  101)) {
        spendableOutputs.add(availableOutputs[i]);
      }
    }

    final lelantusCoins = await mainDB.isar.lelantusCoins
        .where()
        .walletIdEqualTo(walletId)
        .filter()
        .not()
        .valueEqualTo(0.toString())
        .findAll();

    final data = await mainDB
        .getTransactions(walletId)
        .filter()
        .isLelantusIsNull()
        .or()
        .isLelantusEqualTo(false)
        .findAll();

    for (final value in data) {
      if (value.inputs.isNotEmpty) {
        for (var element in value.inputs) {
          if (lelantusCoins.any((e) => e.txid == value.txid) &&
              spendableOutputs.firstWhere(
                      (output) => output?.txid == element.txid,
                      orElse: () => null) !=
                  null) {
            spendableOutputs
                .removeWhere((output) => output!.txid == element.txid);
          }
        }
      }
    }

    // If there is no Utxos to mint then stop the function.
    if (spendableOutputs.isEmpty) {
      throw Exception("_mintSelection(): No spendable outputs found");
    }

    int satoshisBeingUsed = 0;
    Set<UTXO> utxoObjectsToUse = {};

    for (var i = 0; i < spendableOutputs.length; i++) {
      final spendable = spendableOutputs[i];
      if (spendable != null) {
        utxoObjectsToUse.add(spendable);
        satoshisBeingUsed += spendable.value;
      }
    }

    var mintsWithoutFee = await _createMintsFromAmount(satoshisBeingUsed);

    TxData txData = await buildMintTransaction(
      txData: TxData(
        utxos: utxoObjectsToUse,
        mintsMapLelantus: mintsWithoutFee,
      ),
    );

    final Decimal dvSize = Decimal.fromInt(txData.vSize!);

    final feesObject = await fees;

    final Decimal fastFee = Amount(
      rawValue: BigInt.from(feesObject.fast),
      fractionDigits: cryptoCurrency.fractionDigits,
    ).decimal;
    int firoFee =
        (dvSize * fastFee * Decimal.fromInt(100000)).toDouble().ceil();
    // int firoFee = (vSize * feesObject.fast * (1 / 1000.0) * 100000000).ceil();

    if (firoFee < txData.vSize!) {
      firoFee = txData.vSize! + 1;
    }
    firoFee = firoFee + 10;
    final int satoshiAmountToSend = satoshisBeingUsed - firoFee;

    final mintsWithFee = await _createMintsFromAmount(satoshiAmountToSend);

    txData = await buildMintTransaction(
      txData: txData.copyWith(
        mintsMapLelantus: mintsWithFee,
      ),
    );

    return txData;
  }

  Future<List<Map<String, dynamic>>> _createMintsFromAmount(int total) async {
    if (total > LelantusFfiWrapper.MINT_LIMIT) {
      throw Exception(
          "Lelantus mints of more than 5001 are currently disabled");
    }

    int tmpTotal = total;
    int counter = 0;
    final lastUsedIndex =
        await mainDB.getHighestUsedMintIndex(walletId: walletId);
    final nextFreeMintIndex = (lastUsedIndex ?? 0) + 1;

    final isTestnet = cryptoCurrency.network == CryptoCurrencyNetwork.test;

    final root = await getRootHDNode();

    final mints = <Map<String, dynamic>>[];
    while (tmpTotal > 0) {
      final index = nextFreeMintIndex + counter;

      final mintKeyPair = root.derivePath(
        cryptoCurrency.constructDerivePath(
          derivePathType: DerivePathType.bip44,
          chain: LelantusFfiWrapper.MINT_INDEX,
          index: index,
        ),
      );

      final privateKeyHex = mintKeyPair.privateKey.data.toHex;
      final seedId = Format.uint8listToString(mintKeyPair.identifier);

      final String mintTag = lelantus.CreateTag(
        privateKeyHex,
        index,
        seedId,
        isTestnet: isTestnet,
      );
      final List<Map<String, dynamic>> anonymitySets;
      try {
        anonymitySets = await fetchAnonymitySets();
      } catch (e, s) {
        Logging.instance.log(
          "Firo needs better internet to create mints: $e\n$s",
          level: LogLevel.Fatal,
        );
        rethrow;
      }

      bool isUsedMintTag = false;

      // stupid dynamic maps
      for (final set in anonymitySets) {
        final setCoins = set["coins"] as List;
        for (final coin in setCoins) {
          if (coin[1] == mintTag) {
            isUsedMintTag = true;
            break;
          }
        }
        if (isUsedMintTag) {
          break;
        }
      }

      if (isUsedMintTag) {
        Logging.instance.log(
          "Found used index when minting",
          level: LogLevel.Warning,
        );
      }

      if (!isUsedMintTag) {
        final mintValue = min(
            tmpTotal,
            (isTestnet
                ? LelantusFfiWrapper.MINT_LIMIT_TESTNET
                : LelantusFfiWrapper.MINT_LIMIT));
        final mint = await LelantusFfiWrapper.getMintScript(
          amount: Amount(
            rawValue: BigInt.from(mintValue),
            fractionDigits: cryptoCurrency.fractionDigits,
          ),
          privateKeyHex: privateKeyHex,
          index: index,
          seedId: seedId,
          isTestNet: isTestnet,
        );

        mints.add({
          "value": mintValue,
          "script": mint,
          "index": index,
        });
        tmpTotal = tmpTotal -
            (isTestnet
                ? LelantusFfiWrapper.MINT_LIMIT_TESTNET
                : LelantusFfiWrapper.MINT_LIMIT);
      }

      counter++;
    }
    return mints;
  }

  Future<void> anonymizeAllLelantus() async {
    try {
      final mintResult = await _mintSelection();

      await confirmSendLelantus(txData: mintResult);

      unawaited(refresh());
    } catch (e, s) {
      Logging.instance.log(
        "Exception caught in anonymizeAllLelantus(): $e\n$s",
        level: LogLevel.Warning,
      );
      rethrow;
    }
  }

  @override
  Future<void> updateBalance() async {
    // call to super to update transparent balance
    final normalBalanceFuture = super.updateBalance();

    final lelantusCoins = await mainDB.isar.lelantusCoins
        .where()
        .walletIdEqualTo(walletId)
        .filter()
        .isUsedEqualTo(false)
        .not()
        .valueEqualTo(0.toString())
        .findAll();

    final currentChainHeight = await chainHeight;
    int intLelantusBalance = 0;
    int unconfirmedLelantusBalance = 0;

    for (final lelantusCoin in lelantusCoins) {
      final Transaction? txn = mainDB.isar.transactions
          .where()
          .txidWalletIdEqualTo(
            lelantusCoin.txid,
            walletId,
          )
          .findFirstSync();

      if (txn == null) {
        Logging.instance.log(
          "Transaction not found in DB for lelantus coin: $lelantusCoin",
          level: LogLevel.Fatal,
        );
      } else {
        if (txn.isLelantus != true) {
          Logging.instance.log(
            "Bad database state found in ${info.name} $walletId for _refreshBalance lelantus",
            level: LogLevel.Fatal,
          );
        }

        if (txn.isConfirmed(currentChainHeight, cryptoCurrency.minConfirms)) {
          // mint tx, add value to balance
          intLelantusBalance += int.parse(lelantusCoin.value);
        } else {
          unconfirmedLelantusBalance += int.parse(lelantusCoin.value);
        }
      }
    }

    final balancePrivate = Balance(
      total: Amount(
        rawValue: BigInt.from(intLelantusBalance + unconfirmedLelantusBalance),
        fractionDigits: cryptoCurrency.fractionDigits,
      ),
      spendable: Amount(
        rawValue: BigInt.from(intLelantusBalance),
        fractionDigits: cryptoCurrency.fractionDigits,
      ),
      blockedTotal: Amount(
        rawValue: BigInt.zero,
        fractionDigits: cryptoCurrency.fractionDigits,
      ),
      pendingSpendable: Amount(
        rawValue: BigInt.from(unconfirmedLelantusBalance),
        fractionDigits: cryptoCurrency.fractionDigits,
      ),
    );
    await info.updateBalanceSecondary(
      newBalance: balancePrivate,
      isar: mainDB.isar,
    );

    // wait for updated uxtos to get updated public balance
    await normalBalanceFuture;
  }
}
