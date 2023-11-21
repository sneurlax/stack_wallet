import 'package:bitcoindart/bitcoindart.dart' as bitcoindart;
import 'package:coinlib_flutter/coinlib_flutter.dart' as coinlib;
import 'package:flutter/foundation.dart';
import 'package:lelantus/lelantus.dart' as lelantus;
import 'package:stackwallet/models/isar/models/isar_models.dart' as isar_models;
import 'package:stackwallet/models/isar/models/isar_models.dart';
import 'package:stackwallet/models/lelantus_fee_data.dart';
import 'package:stackwallet/utilities/amount/amount.dart';
import 'package:stackwallet/utilities/extensions/impl/uint8_list.dart';
import 'package:stackwallet/utilities/format.dart';
import 'package:stackwallet/utilities/logger.dart';
import 'package:stackwallet/wallets/crypto_currency/crypto_currency.dart';
import 'package:stackwallet/wallets/crypto_currency/intermediate/bip39_hd_currency.dart';
import 'package:stackwallet/wallets/models/tx_data.dart';

abstract final class LelantusFfiWrapper {
  static const MINT_LIMIT = 5001 * 100000000;
  static const MINT_LIMIT_TESTNET = 1001 * 100000000;

  static const JMINT_INDEX = 5;
  static const MINT_INDEX = 2;
  static const TRANSACTION_LELANTUS = 8;
  static const ANONYMITY_SET_EMPTY_ID = 0;

  // partialDerivationPath should be something like "m/$purpose'/$coinType'/$account'/"
  static Future<({List<String> spendTxIds, List<LelantusCoin> lelantusCoins})>
      restore({
    required final String hexRootPrivateKey,
    required final Uint8List chaincode,
    required final Bip39HDCurrency cryptoCurrency,
    required final int latestSetId,
    required final Map<dynamic, dynamic> setDataMap,
    required final List<String> usedSerialNumbers,
    required final String walletId,
    required final String partialDerivationPath,
  }) async {
    final args = (
      hexRootPrivateKey: hexRootPrivateKey,
      chaincode: chaincode,
      cryptoCurrency: cryptoCurrency,
      latestSetId: latestSetId,
      setDataMap: setDataMap,
      usedSerialNumbers: usedSerialNumbers,
      walletId: walletId,
      partialDerivationPath: partialDerivationPath,
    );

    return await compute(_restore, args);
  }

  // partialDerivationPath should be something like "m/$purpose'/$coinType'/$account'/"
  static Future<({List<String> spendTxIds, List<LelantusCoin> lelantusCoins})>
      _restore(
          ({
            String hexRootPrivateKey,
            Uint8List chaincode,
            Bip39HDCurrency cryptoCurrency,
            int latestSetId,
            Map<dynamic, dynamic> setDataMap,
            List<String> usedSerialNumbers,
            String walletId,
            String partialDerivationPath,
          }) args) async {
    List<int> jindexes = [];
    List<isar_models.LelantusCoin> lelantusCoins = [];

    final List<String> spendTxIds = [];
    int lastFoundIndex = 0;
    int currentIndex = 0;

    try {
      Set<String> usedSerialNumbersSet = args.usedSerialNumbers.toSet();

      final root = coinlib.HDPrivateKey.fromKeyAndChainCode(
        coinlib.ECPrivateKey.fromHex(args.hexRootPrivateKey),
        args.chaincode,
      );

      while (currentIndex < lastFoundIndex + 50) {
        final _derivePath =
            "${args.partialDerivationPath}$MINT_INDEX/$currentIndex";

        final mintKeyPair = root.derivePath(_derivePath);

        final String mintTag = lelantus.CreateTag(
          mintKeyPair.privateKey.data.toHex,
          // Format.uint8listToString(mintKeyPair.privateKey!),
          currentIndex,
          Format.uint8listToString(mintKeyPair.identifier),
          isTestnet: args.cryptoCurrency.network == CryptoCurrencyNetwork.test,
        );

        for (int setId = 1; setId <= args.latestSetId; setId++) {
          final setData = args.setDataMap[setId] as Map;
          final foundCoin = (setData["coins"] as List).firstWhere(
            (e) => e[1] == mintTag,
            orElse: () => <Object>[],
          );

          if (foundCoin.length == 4) {
            lastFoundIndex = currentIndex;

            final String publicCoin = foundCoin[0] as String;
            final String txId = foundCoin[3] as String;

            // this value will either be an int or a String
            final dynamic thirdValue = foundCoin[2];

            if (thirdValue is int) {
              final int amount = thirdValue;
              final String serialNumber = lelantus.GetSerialNumber(
                amount,
                mintKeyPair.privateKey.data.toHex,
                // Format.uint8listToString(mintKeyPair.privateKey!),
                currentIndex,
                isTestnet:
                    args.cryptoCurrency.network == CryptoCurrencyNetwork.test,
              );
              final bool isUsed = usedSerialNumbersSet.contains(serialNumber);

              lelantusCoins.removeWhere((e) =>
                  e.txid == txId &&
                  e.mintIndex == currentIndex &&
                  e.anonymitySetId != setId);

              lelantusCoins.add(
                isar_models.LelantusCoin(
                  walletId: args.walletId,
                  mintIndex: currentIndex,
                  value: amount.toString(),
                  txid: txId,
                  anonymitySetId: setId,
                  isUsed: isUsed,
                  isJMint: false,
                  otherData:
                      publicCoin, // not really needed but saved just in case
                ),
              );
              Logging.instance.log(
                "amount $amount used $isUsed",
                level: LogLevel.Info,
              );
            } else if (thirdValue is String) {
              final int keyPath = lelantus.GetAesKeyPath(publicCoin);

              final derivePath =
                  "${args.partialDerivationPath}$JMINT_INDEX/$keyPath";

              final aesKeyPair = root.derivePath(derivePath);

              try {
                final String aesPrivateKey = aesKeyPair.privateKey.data.toHex;

                final int amount = lelantus.decryptMintAmount(
                  aesPrivateKey,
                  thirdValue,
                );

                final String serialNumber = lelantus.GetSerialNumber(
                  amount,
                  aesKeyPair.privateKey.data.toHex,
                  currentIndex,
                  isTestnet:
                      args.cryptoCurrency.network == CryptoCurrencyNetwork.test,
                );
                bool isUsed = usedSerialNumbersSet.contains(serialNumber);
                lelantusCoins.removeWhere((e) =>
                    e.txid == txId &&
                    e.mintIndex == currentIndex &&
                    e.anonymitySetId != setId);

                lelantusCoins.add(
                  isar_models.LelantusCoin(
                    walletId: args.walletId,
                    mintIndex: currentIndex,
                    value: amount.toString(),
                    txid: txId,
                    anonymitySetId: setId,
                    isUsed: isUsed,
                    isJMint: true,
                    otherData:
                        publicCoin, // not really needed but saved just in case
                  ),
                );
                jindexes.add(currentIndex);

                spendTxIds.add(txId);
              } catch (_) {
                Logging.instance.log(
                  "AES keypair derivation issue for derive path: $derivePath",
                  level: LogLevel.Warning,
                );
              }
            } else {
              Logging.instance.log(
                "Unexpected coin found: $foundCoin",
                level: LogLevel.Warning,
              );
            }
          }
        }

        currentIndex++;
      }
    } catch (e, s) {
      Logging.instance.log("Exception rethrown from isolateRestore(): $e\n$s",
          level: LogLevel.Info);
      rethrow;
    }

    return (spendTxIds: spendTxIds, lelantusCoins: lelantusCoins);
  }

  static Future<LelantusFeeData> estimateJoinSplitFee({
    required Amount spendAmount,
    required bool subtractFeeFromAmount,
    required List<lelantus.DartLelantusEntry> lelantusEntries,
    required bool isTestNet,
  }) async {
    return await compute(
      LelantusFfiWrapper._estimateJoinSplitFee,
      (
        spendAmount: spendAmount.raw.toInt(),
        subtractFeeFromAmount: subtractFeeFromAmount,
        lelantusEntries: lelantusEntries,
        isTestNet: isTestNet,
      ),
    );
  }

  static Future<LelantusFeeData> _estimateJoinSplitFee(
      ({
        int spendAmount,
        bool subtractFeeFromAmount,
        List<lelantus.DartLelantusEntry> lelantusEntries,
        bool isTestNet,
      }) data) async {
    Logging.instance.log("estimateJoinsplit fee", level: LogLevel.Info);
    // for (int i = 0; i < lelantusEntries.length; i++) {
    //   Logging.instance.log(lelantusEntries[i], addToDebugMessagesDB: false);
    // }
    Logging.instance.log(
      "${data.spendAmount} ${data.subtractFeeFromAmount}",
      level: LogLevel.Info,
    );

    List<int> changeToMint = List.empty(growable: true);
    List<int> spendCoinIndexes = List.empty(growable: true);
    // Logging.instance.log(lelantusEntries, addToDebugMessagesDB: false);
    final fee = lelantus.estimateFee(
      data.spendAmount,
      data.subtractFeeFromAmount,
      data.lelantusEntries,
      changeToMint,
      spendCoinIndexes,
      isTestnet: data.isTestNet,
    );

    final estimateFeeData =
        LelantusFeeData(changeToMint[0], fee, spendCoinIndexes);
    Logging.instance.log(
      "estimateFeeData ${estimateFeeData.changeToMint}"
      " ${estimateFeeData.fee}"
      " ${estimateFeeData.spendCoinIndexes}",
      level: LogLevel.Info,
    );
    return estimateFeeData;
  }

  static Future<TxData> createJoinSplitTransaction({
    required TxData txData,
    required bool subtractFeeFromAmount,
    required int nextFreeMintIndex,
    required int locktime, // set to current chain height
    required List<lelantus.DartLelantusEntry> lelantusEntries,
    required List<Map<String, dynamic>> anonymitySets,
    required Bip39HDCurrency cryptoCurrency,
    required String partialDerivationPath,
    required String hexRootPrivateKey,
    required Uint8List chaincode,
  }) async {
    final arg = (
      txData: txData,
      subtractFeeFromAmount: subtractFeeFromAmount,
      index: nextFreeMintIndex,
      lelantusEntries: lelantusEntries,
      locktime: locktime,
      cryptoCurrency: cryptoCurrency,
      anonymitySetsArg: anonymitySets,
      partialDerivationPath: partialDerivationPath,
      hexRootPrivateKey: hexRootPrivateKey,
      chaincode: chaincode,
    );

    return await compute(_createJoinSplitTransaction, arg);
  }

  static Future<TxData> _createJoinSplitTransaction(
      ({
        TxData txData,
        bool subtractFeeFromAmount,
        int index,
        List<lelantus.DartLelantusEntry> lelantusEntries,
        int locktime,
        Bip39HDCurrency cryptoCurrency,
        List<Map<dynamic, dynamic>> anonymitySetsArg,
        String partialDerivationPath,
        String hexRootPrivateKey,
        Uint8List chaincode,
      }) arg) async {
    final spendAmount = arg.txData.recipients!.first.amount.raw.toInt();
    final address = arg.txData.recipients!.first.address;

    final estimateJoinSplitFee = await _estimateJoinSplitFee(
      (
        spendAmount: spendAmount,
        subtractFeeFromAmount: arg.subtractFeeFromAmount,
        lelantusEntries: arg.lelantusEntries,
        isTestNet: arg.cryptoCurrency.network == CryptoCurrencyNetwork.test,
      ),
    );
    var changeToMint = estimateJoinSplitFee.changeToMint;
    var fee = estimateJoinSplitFee.fee;
    var spendCoinIndexes = estimateJoinSplitFee.spendCoinIndexes;
    Logging.instance
        .log("$changeToMint $fee $spendCoinIndexes", level: LogLevel.Info);
    if (spendCoinIndexes.isEmpty) {
      throw Exception("Error, Not enough funds.");
    }

    final params = arg.cryptoCurrency.networkParams;
    final _network = bitcoindart.NetworkType(
      messagePrefix: params.messagePrefix,
      bech32: params.bech32Hrp,
      bip32: bitcoindart.Bip32Type(
        public: params.pubHDPrefix,
        private: params.privHDPrefix,
      ),
      pubKeyHash: params.p2pkhPrefix,
      scriptHash: params.p2shPrefix,
      wif: params.wifPrefix,
    );

    final tx = bitcoindart.TransactionBuilder(network: _network);
    tx.setLockTime(arg.locktime);

    tx.setVersion(3 | (TRANSACTION_LELANTUS << 16));

    tx.addInput(
      '0000000000000000000000000000000000000000000000000000000000000000',
      4294967295,
      4294967295,
      Uint8List(0),
    );
    final derivePath = "${arg.partialDerivationPath}$MINT_INDEX/${arg.index}";

    final root = coinlib.HDPrivateKey.fromKeyAndChainCode(
      coinlib.ECPrivateKey.fromHex(arg.hexRootPrivateKey),
      arg.chaincode,
    );

    final jmintKeyPair = root.derivePath(derivePath);

    final String jmintprivatekey = jmintKeyPair.privateKey.data.toHex;

    final keyPath = lelantus.getMintKeyPath(
      changeToMint,
      jmintprivatekey,
      arg.index,
      isTestnet: arg.cryptoCurrency.network == CryptoCurrencyNetwork.test,
    );

    final _derivePath = "${arg.partialDerivationPath}$JMINT_INDEX/$keyPath";

    final aesKeyPair = root.derivePath(_derivePath);
    final aesPrivateKey = aesKeyPair.privateKey.data.toHex;

    final jmintData = lelantus.createJMintScript(
      changeToMint,
      jmintprivatekey,
      arg.index,
      Format.uint8listToString(jmintKeyPair.identifier),
      aesPrivateKey,
      isTestnet: arg.cryptoCurrency.network == CryptoCurrencyNetwork.test,
    );

    tx.addOutput(
      Format.stringToUint8List(jmintData),
      0,
    );

    int amount = spendAmount;
    if (arg.subtractFeeFromAmount) {
      amount -= fee;
    }
    tx.addOutput(
      address,
      amount,
    );

    final extractedTx = tx.buildIncomplete();
    extractedTx.setPayload(Uint8List(0));
    final txHash = extractedTx.getId();

    final List<int> setIds = [];
    final List<List<String>> anonymitySets = [];
    final List<String> anonymitySetHashes = [];
    final List<String> groupBlockHashes = [];
    for (var i = 0; i < arg.lelantusEntries.length; i++) {
      final anonymitySetId = arg.lelantusEntries[i].anonymitySetId;
      if (!setIds.contains(anonymitySetId)) {
        setIds.add(anonymitySetId);
        final anonymitySet = arg.anonymitySetsArg.firstWhere(
            (element) => element["setId"] == anonymitySetId,
            orElse: () => <String, dynamic>{});
        if (anonymitySet.isNotEmpty) {
          anonymitySetHashes.add(anonymitySet['setHash'] as String);
          groupBlockHashes.add(anonymitySet['blockHash'] as String);
          List<String> list = [];
          for (int i = 0; i < (anonymitySet['coins'] as List).length; i++) {
            list.add(anonymitySet['coins'][i][0] as String);
          }
          anonymitySets.add(list);
        }
      }
    }

    final String spendScript = lelantus.createJoinSplitScript(
      txHash,
      spendAmount,
      arg.subtractFeeFromAmount,
      jmintprivatekey,
      arg.index,
      arg.lelantusEntries,
      setIds,
      anonymitySets,
      anonymitySetHashes,
      groupBlockHashes,
      isTestnet: arg.cryptoCurrency.network == CryptoCurrencyNetwork.test,
    );

    final finalTx = bitcoindart.TransactionBuilder(network: _network);
    finalTx.setLockTime(arg.locktime);

    finalTx.setVersion(3 | (TRANSACTION_LELANTUS << 16));

    finalTx.addOutput(
      Format.stringToUint8List(jmintData),
      0,
    );

    finalTx.addOutput(
      address,
      amount,
    );

    final extTx = finalTx.buildIncomplete();
    extTx.addInput(
      Format.stringToUint8List(
          '0000000000000000000000000000000000000000000000000000000000000000'),
      4294967295,
      4294967295,
      Format.stringToUint8List("c9"),
    );
    // debugPrint("spendscript: $spendScript");
    extTx.setPayload(Format.stringToUint8List(spendScript));

    final txHex = extTx.toHex();
    final txId = extTx.getId();
    Logging.instance.log("txid  $txId", level: LogLevel.Info);
    Logging.instance.log("txHex: $txHex", level: LogLevel.Info);

    final amountAmount = Amount(
      rawValue: BigInt.from(amount),
      fractionDigits: arg.cryptoCurrency.fractionDigits,
    );

    return arg.txData.copyWith(
      txid: txId,
      raw: txHex,
      recipients: [(address: address, amount: amountAmount)],
      fee: Amount(
        rawValue: BigInt.from(fee),
        fractionDigits: arg.cryptoCurrency.fractionDigits,
      ),
      vSize: extTx.virtualSize(),
      jMintValue: changeToMint,
      spendCoinIndexes: spendCoinIndexes,
      height: arg.locktime,
      txType: TransactionType.outgoing,
      txSubType: TransactionSubType.join,
      // "confirmed_status": false,
      // "timestamp": DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    // return {
    //   "txid": txId,
    //   "txHex": txHex,
    //   "value": amount,
    //   "fees": Amount(
    //     rawValue: BigInt.from(fee),
    //     fractionDigits: arg.cryptoCurrency.fractionDigits,
    //   ).decimal.toDouble(),
    //   "fee": fee,
    //   "vSize": extTx.virtualSize(),
    //   "jmintValue": changeToMint,
    //   "spendCoinIndexes": spendCoinIndexes,
    //   "height": arg.locktime,
    //   "txType": "Sent",
    //   "confirmed_status": false,
    //   "amount": amountAmount.decimal.toDouble(),
    //   "recipientAmt": amountAmount,
    //   "address": arg.address,
    //   "timestamp": DateTime.now().millisecondsSinceEpoch ~/ 1000,
    //   "subType": "join",
    // };
  }

  // ===========================================================================

  static Future<String> _getMintScriptWrapper(
      ({
        int amount,
        String privateKeyHex,
        int index,
        String seedId,
        bool isTestNet
      }) data) async {
    String mintHex = lelantus.getMintScript(
      data.amount,
      data.privateKeyHex,
      data.index,
      data.seedId,
      isTestnet: data.isTestNet,
    );
    return mintHex;
  }

  static Future<String> getMintScript({
    required Amount amount,
    required String privateKeyHex,
    required int index,
    required String seedId,
    required bool isTestNet,
  }) async {
    return await compute(
      LelantusFfiWrapper._getMintScriptWrapper,
      (
        amount: amount.raw.toInt(),
        privateKeyHex: privateKeyHex,
        index: index,
        seedId: seedId,
        isTestNet: isTestNet
      ),
    );
  }
}