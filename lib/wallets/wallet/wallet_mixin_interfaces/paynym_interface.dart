import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip47/bip47.dart';
import 'package:bip47/src/util.dart';
import 'package:bitcoindart/bitcoindart.dart' as btc_dart;
import 'package:bitcoindart/src/utils/constants/op.dart' as op;
import 'package:bitcoindart/src/utils/script.dart' as bscript;
import 'package:isar/isar.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:stackwallet/exceptions/wallet/insufficient_balance_exception.dart';
import 'package:stackwallet/exceptions/wallet/paynym_send_exception.dart';
import 'package:stackwallet/models/isar/models/isar_models.dart';
import 'package:stackwallet/models/signing_data.dart';
import 'package:stackwallet/utilities/amount/amount.dart';
import 'package:stackwallet/utilities/bip32_utils.dart';
import 'package:stackwallet/utilities/bip47_utils.dart';
import 'package:stackwallet/utilities/enums/coin_enum.dart';
import 'package:stackwallet/utilities/format.dart';
import 'package:stackwallet/utilities/logger.dart';
import 'package:stackwallet/wallets/models/tx_data.dart';
import 'package:stackwallet/wallets/wallet/intermediate/bip39_hd_wallet.dart';
import 'package:stackwallet/wallets/wallet/wallet_mixin_interfaces/electrumx_interface.dart';
import 'package:tuple/tuple.dart';

const String kPCodeKeyPrefix = "pCode_key_";

String _basePaynymDerivePath({required bool testnet}) =>
    "m/47'/${testnet ? "1" : "0"}'/0'";
String _notificationDerivationPath({required bool testnet}) =>
    "${_basePaynymDerivePath(testnet: testnet)}/0";

String _receivingPaynymAddressDerivationPath(
  int index, {
  required bool testnet,
}) =>
    "${_basePaynymDerivePath(testnet: testnet)}/$index/0";
String _sendPaynymAddressDerivationPath(
  int index, {
  required bool testnet,
}) =>
    "${_basePaynymDerivePath(testnet: testnet)}/0/$index";

mixin PaynymInterface on Bip39HDWallet, ElectrumXInterface {
  Amount get _dustLimitP2PKH => Amount(
        rawValue: BigInt.from(546),
        fractionDigits: cryptoCurrency.fractionDigits,
      );

  btc_dart.NetworkType get networkType => btc_dart.NetworkType(
        messagePrefix: cryptoCurrency.networkParams.messagePrefix,
        bech32: cryptoCurrency.networkParams.bech32Hrp,
        bip32: btc_dart.Bip32Type(
          public: cryptoCurrency.networkParams.pubHDPrefix,
          private: cryptoCurrency.networkParams.privHDPrefix,
        ),
        pubKeyHash: cryptoCurrency.networkParams.p2pkhPrefix,
        scriptHash: cryptoCurrency.networkParams.p2shPrefix,
        wif: cryptoCurrency.networkParams.wifPrefix,
      );

  Future<bip32.BIP32> getBip47BaseNode() async {
    final root = await _getRootNode();
    final node = root.derivePath(
      _basePaynymDerivePath(
        testnet: info.coin.isTestNet,
      ),
    );
    return node;
  }

  Future<Uint8List> getPrivateKeyForPaynymReceivingAddress({
    required String paymentCodeString,
    required int index,
  }) async {
    final bip47base = await getBip47BaseNode();

    final paymentAddress = PaymentAddress(
      bip32Node: bip47base.derive(index),
      paymentCode: PaymentCode.fromPaymentCode(
        paymentCodeString,
        networkType: networkType,
      ),
      networkType: networkType,
      index: 0,
    );

    final pair = paymentAddress.getReceiveAddressKeyPair();

    return pair.privateKey!;
  }

  Future<Address> currentReceivingPaynymAddress({
    required PaymentCode sender,
    required bool isSegwit,
  }) async {
    final keys = await lookupKey(sender.toString());

    final address = await mainDB
        .getAddresses(walletId)
        .filter()
        .subTypeEqualTo(AddressSubType.paynymReceive)
        .and()
        .group((q) {
          if (isSegwit) {
            return q
                .typeEqualTo(AddressType.p2sh)
                .or()
                .typeEqualTo(AddressType.p2wpkh);
          } else {
            return q.typeEqualTo(AddressType.p2pkh);
          }
        })
        .and()
        .anyOf<String, Address>(keys, (q, String e) => q.otherDataEqualTo(e))
        .sortByDerivationIndexDesc()
        .findFirst();

    if (address == null) {
      final generatedAddress = await _generatePaynymReceivingAddress(
        sender: sender,
        index: 0,
        generateSegwitAddress: isSegwit,
      );

      final existing = await mainDB
          .getAddresses(walletId)
          .filter()
          .valueEqualTo(generatedAddress.value)
          .findFirst();

      if (existing == null) {
        // Add that new address
        await mainDB.putAddress(generatedAddress);
      } else {
        // we need to update the address
        await mainDB.updateAddress(existing, generatedAddress);
      }

      return currentReceivingPaynymAddress(
        isSegwit: isSegwit,
        sender: sender,
      );
    } else {
      return address;
    }
  }

  Future<Address> _generatePaynymReceivingAddress({
    required PaymentCode sender,
    required int index,
    required bool generateSegwitAddress,
  }) async {
    final root = await _getRootNode();
    final node = root.derivePath(
      _basePaynymDerivePath(
        testnet: info.coin.isTestNet,
      ),
    );

    final paymentAddress = PaymentAddress(
      bip32Node: node.derive(index),
      paymentCode: sender,
      networkType: networkType,
      index: 0,
    );

    final addressString = generateSegwitAddress
        ? paymentAddress.getReceiveAddressP2WPKH()
        : paymentAddress.getReceiveAddressP2PKH();

    final address = Address(
      walletId: walletId,
      value: addressString,
      publicKey: [],
      derivationIndex: index,
      derivationPath: DerivationPath()
        ..value = _receivingPaynymAddressDerivationPath(
          index,
          testnet: info.coin.isTestNet,
        ),
      type: generateSegwitAddress ? AddressType.p2wpkh : AddressType.p2pkh,
      subType: AddressSubType.paynymReceive,
      otherData: await storeCode(sender.toString()),
    );

    return address;
  }

  Future<Address> _generatePaynymSendAddress({
    required PaymentCode other,
    required int index,
    required bool generateSegwitAddress,
    bip32.BIP32? mySendBip32Node,
  }) async {
    final node = mySendBip32Node ?? await deriveNotificationBip32Node();

    final paymentAddress = PaymentAddress(
      bip32Node: node,
      paymentCode: other,
      networkType: networkType,
      index: index,
    );

    final addressString = generateSegwitAddress
        ? paymentAddress.getSendAddressP2WPKH()
        : paymentAddress.getSendAddressP2PKH();

    final address = Address(
      walletId: walletId,
      value: addressString,
      publicKey: [],
      derivationIndex: index,
      derivationPath: DerivationPath()
        ..value = _sendPaynymAddressDerivationPath(
          index,
          testnet: info.coin.isTestNet,
        ),
      type: AddressType.nonWallet,
      subType: AddressSubType.paynymSend,
      otherData: await storeCode(other.toString()),
    );

    return address;
  }

  Future<void> checkCurrentPaynymReceivingAddressForTransactions({
    required PaymentCode sender,
    required bool isSegwit,
  }) async {
    final address = await currentReceivingPaynymAddress(
      sender: sender,
      isSegwit: isSegwit,
    );

    final txCount = await fetchTxCount(
      addressScriptHash: cryptoCurrency.addressToScriptHash(
        address: address.value,
      ),
    );
    if (txCount > 0) {
      // generate next address and add to db
      final nextAddress = await _generatePaynymReceivingAddress(
        sender: sender,
        index: address.derivationIndex + 1,
        generateSegwitAddress: isSegwit,
      );

      final existing = await mainDB
          .getAddresses(walletId)
          .filter()
          .valueEqualTo(nextAddress.value)
          .findFirst();

      if (existing == null) {
        // Add that new address
        await mainDB.putAddress(nextAddress);
      } else {
        // we need to update the address
        await mainDB.updateAddress(existing, nextAddress);
      }
      // keep checking until address with no tx history is set as current
      await checkCurrentPaynymReceivingAddressForTransactions(
        sender: sender,
        isSegwit: isSegwit,
      );
    }
  }

  Future<void> checkAllCurrentReceivingPaynymAddressesForTransactions() async {
    final codes = await getAllPaymentCodesFromNotificationTransactions();
    final List<Future<void>> futures = [];
    for (final code in codes) {
      futures.add(checkCurrentPaynymReceivingAddressForTransactions(
        sender: code,
        isSegwit: true,
      ));
      futures.add(checkCurrentPaynymReceivingAddressForTransactions(
        sender: code,
        isSegwit: false,
      ));
    }
    await Future.wait(futures);
  }

  // generate bip32 payment code root
  Future<bip32.BIP32> _getRootNode() async {
    return _cachedRootNode ??= await Bip32Utils.getBip32Root(
      (await getMnemonic()),
      (await getMnemonicPassphrase()),
      networkType,
    );
  }

  bip32.BIP32? _cachedRootNode;

  Future<bip32.BIP32> deriveNotificationBip32Node() async {
    final root = await _getRootNode();
    final node = root
        .derivePath(
          _basePaynymDerivePath(
            testnet: info.coin.isTestNet,
          ),
        )
        .derive(0);
    return node;
  }

  /// fetch or generate this wallet's bip47 payment code
  Future<PaymentCode> getPaymentCode({
    required bool isSegwit,
  }) async {
    final node = await _getRootNode();

    final paymentCode = PaymentCode.fromBip32Node(
      node.derivePath(_basePaynymDerivePath(testnet: info.coin.isTestNet)),
      networkType: networkType,
      shouldSetSegwitBit: isSegwit,
    );

    return paymentCode;
  }

  Future<Uint8List> signWithNotificationKey(Uint8List data) async {
    final myPrivateKeyNode = await deriveNotificationBip32Node();
    final pair = btc_dart.ECPair.fromPrivateKey(myPrivateKeyNode.privateKey!,
        network: networkType);
    final signed = pair.sign(SHA256Digest().process(data));
    return signed;
  }

  Future<String> signStringWithNotificationKey(String data) async {
    final bytes =
        await signWithNotificationKey(Uint8List.fromList(utf8.encode(data)));
    return Format.uint8listToString(bytes);
  }

  Future<TxData> preparePaymentCodeSend({
    required TxData txData,
    // required PaymentCode paymentCode,
    // required bool isSegwit,
    // required Amount amount,
    // Map<String, dynamic>? args,
  }) async {
    // TODO: handle asserts in a better manner
    assert(txData.recipients != null && txData.recipients!.length == 1);
    assert(txData.paynymAccountLite!.code == txData.recipients!.first.address);

    final paymentCode = PaymentCode.fromPaymentCode(
      txData.paynymAccountLite!.code,
      networkType: networkType,
    );

    if (!(await hasConnected(txData.paynymAccountLite!.code.toString()))) {
      throw PaynymSendException(
          "No notification transaction sent to $paymentCode,");
    } else {
      final myPrivateKeyNode = await deriveNotificationBip32Node();
      final sendToAddress = await nextUnusedSendAddressFrom(
        pCode: paymentCode,
        privateKeyNode: myPrivateKeyNode,
        isSegwit: txData.paynymAccountLite!.segwit,
      );

      return prepareSend(
        txData: txData.copyWith(
          recipients: [
            (
              address: sendToAddress.value,
              amount: txData.recipients!.first.amount,
              isChange: false,
            ),
          ],
        ),
      );
    }
  }

  /// get the next unused address to send to given the receiver's payment code
  /// and your own private key
  Future<Address> nextUnusedSendAddressFrom({
    required PaymentCode pCode,
    required bool isSegwit,
    required bip32.BIP32 privateKeyNode,
    int startIndex = 0,
  }) async {
    // https://en.bitcoin.it/wiki/BIP_0047#Path_levels
    const maxCount = 2147483647;

    for (int i = startIndex; i < maxCount; i++) {
      final keys = await lookupKey(pCode.toString());
      final address = await mainDB
          .getAddresses(walletId)
          .filter()
          .subTypeEqualTo(AddressSubType.paynymSend)
          .and()
          .anyOf<String, Address>(keys, (q, String e) => q.otherDataEqualTo(e))
          .and()
          .derivationIndexEqualTo(i)
          .findFirst();

      if (address != null) {
        final count = await fetchTxCount(
          addressScriptHash: cryptoCurrency.addressToScriptHash(
            address: address.value,
          ),
        );
        // return address if unused, otherwise continue to next index
        if (count == 0) {
          return address;
        }
      } else {
        final address = await _generatePaynymSendAddress(
          other: pCode,
          index: i,
          generateSegwitAddress: isSegwit,
          mySendBip32Node: privateKeyNode,
        );

        final storedAddress = await mainDB.getAddress(walletId, address.value);
        if (storedAddress == null) {
          await mainDB.putAddress(address);
        } else {
          await mainDB.updateAddress(storedAddress, address);
        }
        final count = await fetchTxCount(
          addressScriptHash: cryptoCurrency.addressToScriptHash(
            address: address.value,
          ),
        );
        // return address if unused, otherwise continue to next index
        if (count == 0) {
          return address;
        }
      }
    }

    throw PaynymSendException("Exhausted unused send addresses!");
  }

  Future<TxData> prepareNotificationTx({
    required int selectedTxFeeRate,
    required String targetPaymentCodeString,
    int additionalOutputs = 0,
    List<UTXO>? utxos,
  }) async {
    try {
      // final amountToSend = cryptoCurrency.dustLimitP2PKH;

      final amountToSend = _dustLimitP2PKH;
      final List<UTXO> availableOutputs =
          utxos ?? await mainDB.getUTXOs(walletId).findAll();
      final List<UTXO> spendableOutputs = [];
      BigInt spendableSatoshiValue = BigInt.zero;

      // Build list of spendable outputs and totaling their satoshi amount
      for (var i = 0; i < availableOutputs.length; i++) {
        if (availableOutputs[i].isBlocked == false &&
            availableOutputs[i].isConfirmed(
                    await fetchChainHeight(), cryptoCurrency.minConfirms) ==
                true) {
          spendableOutputs.add(availableOutputs[i]);
          spendableSatoshiValue += BigInt.from(availableOutputs[i].value);
        }
      }

      if (spendableSatoshiValue < amountToSend.raw) {
        // insufficient balance
        throw InsufficientBalanceException(
            "Spendable balance is less than the minimum required for a notification transaction.");
      } else if (spendableSatoshiValue == amountToSend.raw) {
        // insufficient balance due to missing amount to cover fee
        throw InsufficientBalanceException(
            "Remaining balance does not cover the network fee.");
      }

      // sort spendable by age (oldest first)
      spendableOutputs.sort((a, b) => b.blockTime!.compareTo(a.blockTime!));

      BigInt satoshisBeingUsed = BigInt.zero;
      int outputsBeingUsed = 0;
      List<UTXO> utxoObjectsToUse = [];

      for (int i = 0;
          satoshisBeingUsed < amountToSend.raw && i < spendableOutputs.length;
          i++) {
        utxoObjectsToUse.add(spendableOutputs[i]);
        satoshisBeingUsed += BigInt.from(spendableOutputs[i].value);
        outputsBeingUsed += 1;
      }

      // add additional outputs if required
      for (int i = 0;
          i < additionalOutputs && outputsBeingUsed < spendableOutputs.length;
          i++) {
        utxoObjectsToUse.add(spendableOutputs[outputsBeingUsed]);
        satoshisBeingUsed +=
            BigInt.from(spendableOutputs[outputsBeingUsed].value);
        outputsBeingUsed += 1;
      }

      // gather required signing data
      final utxoSigningData = await fetchBuildTxData(utxoObjectsToUse);

      final vSizeForNoChange = BigInt.from(
        (await _createNotificationTx(
          targetPaymentCodeString: targetPaymentCodeString,
          utxoSigningData: utxoSigningData,
          change: BigInt.zero,
          // override amount to get around absurd fees error
          overrideAmountForTesting: satoshisBeingUsed,
        ))
            .item2,
      );

      final vSizeForWithChange = BigInt.from(
        (await _createNotificationTx(
          targetPaymentCodeString: targetPaymentCodeString,
          utxoSigningData: utxoSigningData,
          change: satoshisBeingUsed - amountToSend.raw,
        ))
            .item2,
      );

      // Assume 2 outputs, for recipient and payment code script
      BigInt feeForNoChange = BigInt.from(
        estimateTxFee(
          vSize: vSizeForNoChange.toInt(),
          feeRatePerKB: selectedTxFeeRate,
        ),
      );

      // Assume 3 outputs, for recipient, payment code script, and change
      BigInt feeForWithChange = BigInt.from(
        estimateTxFee(
          vSize: vSizeForWithChange.toInt(),
          feeRatePerKB: selectedTxFeeRate,
        ),
      );

      if (info.coin == Coin.dogecoin || info.coin == Coin.dogecoinTestNet) {
        if (feeForNoChange < vSizeForNoChange * BigInt.from(1000)) {
          feeForNoChange = vSizeForNoChange * BigInt.from(1000);
        }
        if (feeForWithChange < vSizeForWithChange * BigInt.from(1000)) {
          feeForWithChange = vSizeForWithChange * BigInt.from(1000);
        }
      }

      if (satoshisBeingUsed - amountToSend.raw >
          feeForNoChange + _dustLimitP2PKH.raw) {
        // try to add change output due to "left over" amount being greater than
        // the estimated fee + the dust limit
        BigInt changeAmount =
            satoshisBeingUsed - amountToSend.raw - feeForWithChange;

        // check estimates are correct and build notification tx
        if (changeAmount >= _dustLimitP2PKH.raw &&
            satoshisBeingUsed - amountToSend.raw - changeAmount ==
                feeForWithChange) {
          var txn = await _createNotificationTx(
            targetPaymentCodeString: targetPaymentCodeString,
            utxoSigningData: utxoSigningData,
            change: changeAmount,
          );

          BigInt feeBeingPaid =
              satoshisBeingUsed - amountToSend.raw - changeAmount;

          // make sure minimum fee is accurate if that is being used
          if (txn.item2 - feeBeingPaid.toInt() == 1) {
            changeAmount -= BigInt.one;
            feeBeingPaid += BigInt.one;
            txn = await _createNotificationTx(
              targetPaymentCodeString: targetPaymentCodeString,
              utxoSigningData: utxoSigningData,
              change: changeAmount,
            );
          }

          final txData = TxData(
              raw: txn.item1,
              recipients: [
                (
                  address: targetPaymentCodeString,
                  amount: amountToSend,
                  isChange: false,
                ),
              ],
              fee: Amount(
                rawValue: feeBeingPaid,
                fractionDigits: cryptoCurrency.fractionDigits,
              ),
              vSize: txn.item2,
              utxos: utxoSigningData.map((e) => e.utxo).toSet(),
              note: "PayNym connect");

          return txData;
        } else {
          // something broke during fee estimation or the change amount is smaller
          // than the dust limit. Try without change
          final txn = await _createNotificationTx(
            targetPaymentCodeString: targetPaymentCodeString,
            utxoSigningData: utxoSigningData,
            change: BigInt.zero,
          );

          BigInt feeBeingPaid = satoshisBeingUsed - amountToSend.raw;

          final txData = TxData(
              raw: txn.item1,
              recipients: [
                (
                  address: targetPaymentCodeString,
                  amount: amountToSend,
                  isChange: false,
                )
              ],
              fee: Amount(
                rawValue: feeBeingPaid,
                fractionDigits: cryptoCurrency.fractionDigits,
              ),
              vSize: txn.item2,
              utxos: utxoSigningData.map((e) => e.utxo).toSet(),
              note: "PayNym connect");

          return txData;
        }
      } else if (satoshisBeingUsed - amountToSend.raw >= feeForNoChange) {
        // since we already checked if we need to add a change output we can just
        // build without change here
        final txn = await _createNotificationTx(
          targetPaymentCodeString: targetPaymentCodeString,
          utxoSigningData: utxoSigningData,
          change: BigInt.zero,
        );

        BigInt feeBeingPaid = satoshisBeingUsed - amountToSend.raw;

        final txData = TxData(
            raw: txn.item1,
            recipients: [
              (
                address: targetPaymentCodeString,
                amount: amountToSend,
                isChange: false,
              )
            ],
            fee: Amount(
              rawValue: feeBeingPaid,
              fractionDigits: cryptoCurrency.fractionDigits,
            ),
            vSize: txn.item2,
            utxos: utxoSigningData.map((e) => e.utxo).toSet(),
            note: "PayNym connect");

        return txData;
      } else {
        // if we get here we do not have enough funds to cover the tx total so we
        // check if we have any more available outputs and try again
        if (spendableOutputs.length > outputsBeingUsed) {
          return prepareNotificationTx(
            selectedTxFeeRate: selectedTxFeeRate,
            targetPaymentCodeString: targetPaymentCodeString,
            additionalOutputs: additionalOutputs + 1,
          );
        } else {
          throw InsufficientBalanceException(
              "Remaining balance does not cover the network fee.");
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  // return tuple with string value equal to the raw tx hex and the int value
  // equal to its vSize
  Future<Tuple2<String, int>> _createNotificationTx({
    required String targetPaymentCodeString,
    required List<SigningData> utxoSigningData,
    required BigInt change,
    BigInt? overrideAmountForTesting,
  }) async {
    try {
      final targetPaymentCode = PaymentCode.fromPaymentCode(
        targetPaymentCodeString,
        networkType: networkType,
      );
      final myCode = await getPaymentCode(isSegwit: false);

      final utxo = utxoSigningData.first.utxo;
      final txPoint = utxo.txid.fromHex.reversed.toList();
      final txPointIndex = utxo.vout;

      final rev = Uint8List(txPoint.length + 4);
      Util.copyBytes(Uint8List.fromList(txPoint), 0, rev, 0, txPoint.length);
      final buffer = rev.buffer.asByteData();
      buffer.setUint32(txPoint.length, txPointIndex, Endian.little);

      final myKeyPair = utxoSigningData.first.keyPair!;

      final S = SecretPoint(
        myKeyPair.privateKey!,
        targetPaymentCode.notificationPublicKey(),
      );

      final blindingMask = PaymentCode.getMask(S.ecdhSecret(), rev);

      final blindedPaymentCode = PaymentCode.blind(
        payload: myCode.getPayload(),
        mask: blindingMask,
        unBlind: false,
      );

      final opReturnScript = bscript.compile([
        (op.OPS["OP_RETURN"] as int),
        blindedPaymentCode,
      ]);

      // build a notification tx
      final txb = btc_dart.TransactionBuilder(network: networkType);
      txb.setVersion(1);

      txb.addInput(
        utxo.txid,
        txPointIndex,
        null,
        utxoSigningData.first.output!,
      );

      // add rest of possible inputs
      for (var i = 1; i < utxoSigningData.length; i++) {
        final utxo = utxoSigningData[i].utxo;
        txb.addInput(
          utxo.txid,
          utxo.vout,
          null,
          utxoSigningData[i].output!,
        );
      }
      final String notificationAddress =
          targetPaymentCode.notificationAddressP2PKH();

      txb.addOutput(
        notificationAddress,
        (overrideAmountForTesting ?? _dustLimitP2PKH.raw).toInt(),
      );
      txb.addOutput(opReturnScript, 0);

      // TODO: add possible change output and mark output as dangerous
      if (change > BigInt.zero) {
        // generate new change address if current change address has been used
        await checkChangeAddressForTransactions();
        final String changeAddress = (await getCurrentChangeAddress())!.value;
        txb.addOutput(changeAddress, change.toInt());
      }

      txb.sign(
        vin: 0,
        keyPair: myKeyPair,
        witnessValue: utxo.value,
        witnessScript: utxoSigningData.first.redeemScript,
      );

      // sign rest of possible inputs
      for (var i = 1; i < utxoSigningData.length; i++) {
        txb.sign(
          vin: i,
          keyPair: utxoSigningData[i].keyPair!,
          witnessValue: utxoSigningData[i].utxo.value,
          witnessScript: utxoSigningData[i].redeemScript,
        );
      }

      final builtTx = txb.build();

      return Tuple2(builtTx.toHex(), builtTx.virtualSize());
    } catch (e, s) {
      Logging.instance.log(
        "_createNotificationTx(): $e\n$s",
        level: LogLevel.Error,
      );
      rethrow;
    }
  }

  Future<String> broadcastNotificationTx({
    required Map<String, dynamic> preparedTx,
  }) async {
    try {
      Logging.instance.log("confirmNotificationTx txData: $preparedTx",
          level: LogLevel.Info);
      final txHash = await electrumXClient.broadcastTransaction(
          rawTx: preparedTx["hex"] as String);
      Logging.instance.log("Sent txHash: $txHash", level: LogLevel.Info);

      // TODO: only refresh transaction data
      try {
        await refresh();
      } catch (e) {
        Logging.instance.log(
          "refresh() failed in confirmNotificationTx (${info.name}::$walletId): $e",
          level: LogLevel.Error,
        );
      }

      return txHash;
    } catch (e, s) {
      Logging.instance.log("Exception rethrown from confirmSend(): $e\n$s",
          level: LogLevel.Error);
      rethrow;
    }
  }

  // Future<bool?> _checkHasConnectedCache(String paymentCodeString) async {
  //   final value = await secureStorageInterface.read(
  //       key: "$_connectedKeyPrefix$paymentCodeString");
  //   if (value == null) {
  //     return null;
  //   } else {
  //     final int rawBool = int.parse(value);
  //     return rawBool > 0;
  //   }
  // }
  //
  // Future<void> _setConnectedCache(
  //     String paymentCodeString, bool hasConnected) async {
  //   await secureStorageInterface.write(
  //       key: "$_connectedKeyPrefix$paymentCodeString",
  //       value: hasConnected ? "1" : "0");
  // }

  // TODO optimize
  Future<bool> hasConnected(String paymentCodeString) async {
    // final didConnect = await _checkHasConnectedCache(paymentCodeString);
    // if (didConnect == true) {
    //   return true;
    // }
    //
    // final keys = await lookupKey(paymentCodeString);
    //
    // final tx = await mainDB
    //     .getTransactions(walletId)
    //     .filter()
    //     .subTypeEqualTo(TransactionSubType.bip47Notification).and()
    //     .address((q) =>
    //         q.anyOf<String, Transaction>(keys, (q, e) => q.otherDataEqualTo(e)))
    //     .findAll();

    final myNotificationAddress = await getMyNotificationAddress();

    final txns = await mainDB
        .getTransactions(walletId)
        .filter()
        .subTypeEqualTo(TransactionSubType.bip47Notification)
        .findAll();

    for (final tx in txns) {
      if (tx.type == TransactionType.incoming &&
          tx.address.value?.value == myNotificationAddress.value) {
        final unBlindedPaymentCode = await unBlindedPaymentCodeFromTransaction(
          transaction: tx,
        );

        if (unBlindedPaymentCode != null &&
            paymentCodeString == unBlindedPaymentCode.toString()) {
          // await _setConnectedCache(paymentCodeString, true);
          return true;
        }

        final unBlindedPaymentCodeBad =
            await unBlindedPaymentCodeFromTransactionBad(
          transaction: tx,
        );

        if (unBlindedPaymentCodeBad != null &&
            paymentCodeString == unBlindedPaymentCodeBad.toString()) {
          // await _setConnectedCache(paymentCodeString, true);
          return true;
        }
      } else if (tx.type == TransactionType.outgoing) {
        if (tx.address.value?.otherData != null) {
          final code =
              await paymentCodeStringByKey(tx.address.value!.otherData!);
          if (code == paymentCodeString) {
            // await _setConnectedCache(paymentCodeString, true);
            return true;
          }
        }
      }
    }

    // otherwise return no
    // await _setConnectedCache(paymentCodeString, false);
    return false;
  }

  Uint8List? _pubKeyFromInput(Input input) {
    final scriptSigComponents = input.scriptSigAsm?.split(" ") ?? [];
    if (scriptSigComponents.length > 1) {
      return scriptSigComponents[1].fromHex;
    }
    if (input.witness != null) {
      try {
        final witnessComponents = jsonDecode(input.witness!) as List;
        if (witnessComponents.length == 2) {
          return (witnessComponents[1] as String).fromHex;
        }
      } catch (_) {
        //
      }
    }
    return null;
  }

  Future<PaymentCode?> unBlindedPaymentCodeFromTransaction({
    required Transaction transaction,
  }) async {
    try {
      final blindedCodeBytes =
          Bip47Utils.getBlindedPaymentCodeBytesFrom(transaction);

      // transaction does not contain a payment code
      if (blindedCodeBytes == null) {
        return null;
      }

      final designatedInput = transaction.inputs.first;

      final txPoint = designatedInput.txid.fromHex.reversed.toList();
      final txPointIndex = designatedInput.vout;

      final rev = Uint8List(txPoint.length + 4);
      Util.copyBytes(Uint8List.fromList(txPoint), 0, rev, 0, txPoint.length);
      final buffer = rev.buffer.asByteData();
      buffer.setUint32(txPoint.length, txPointIndex, Endian.little);

      final pubKey = _pubKeyFromInput(designatedInput)!;

      final myPrivateKey = (await deriveNotificationBip32Node()).privateKey!;

      final S = SecretPoint(myPrivateKey, pubKey);

      final mask = PaymentCode.getMask(S.ecdhSecret(), rev);

      final unBlindedPayload = PaymentCode.blind(
        payload: blindedCodeBytes,
        mask: mask,
        unBlind: true,
      );

      final unBlindedPaymentCode = PaymentCode.fromPayload(
        unBlindedPayload,
        networkType: networkType,
      );

      return unBlindedPaymentCode;
    } catch (e) {
      Logging.instance.log(
        "unBlindedPaymentCodeFromTransaction() failed: $e\nFor tx: $transaction",
        level: LogLevel.Warning,
      );
      return null;
    }
  }

  Future<PaymentCode?> unBlindedPaymentCodeFromTransactionBad({
    required Transaction transaction,
  }) async {
    try {
      final blindedCodeBytes =
          Bip47Utils.getBlindedPaymentCodeBytesFrom(transaction);

      // transaction does not contain a payment code
      if (blindedCodeBytes == null) {
        return null;
      }

      final designatedInput = transaction.inputs.first;

      final txPoint = designatedInput.txid.fromHex.toList();
      final txPointIndex = designatedInput.vout;

      final rev = Uint8List(txPoint.length + 4);
      Util.copyBytes(Uint8List.fromList(txPoint), 0, rev, 0, txPoint.length);
      final buffer = rev.buffer.asByteData();
      buffer.setUint32(txPoint.length, txPointIndex, Endian.little);

      final pubKey = _pubKeyFromInput(designatedInput)!;

      final myPrivateKey = (await deriveNotificationBip32Node()).privateKey!;

      final S = SecretPoint(myPrivateKey, pubKey);

      final mask = PaymentCode.getMask(S.ecdhSecret(), rev);

      final unBlindedPayload = PaymentCode.blind(
        payload: blindedCodeBytes,
        mask: mask,
        unBlind: true,
      );

      final unBlindedPaymentCode = PaymentCode.fromPayload(
        unBlindedPayload,
        networkType: networkType,
      );

      return unBlindedPaymentCode;
    } catch (e) {
      Logging.instance.log(
        "unBlindedPaymentCodeFromTransactionBad() failed: $e\nFor tx: $transaction",
        level: LogLevel.Warning,
      );
      return null;
    }
  }

  Future<List<PaymentCode>>
      getAllPaymentCodesFromNotificationTransactions() async {
    final txns = await mainDB
        .getTransactions(walletId)
        .filter()
        .subTypeEqualTo(TransactionSubType.bip47Notification)
        .findAll();

    List<PaymentCode> codes = [];

    for (final tx in txns) {
      // tx is sent so we can check the address's otherData for the code String
      if (tx.type == TransactionType.outgoing &&
          tx.address.value?.otherData != null) {
        final codeString =
            await paymentCodeStringByKey(tx.address.value!.otherData!);
        if (codeString != null &&
            codes.where((e) => e.toString() == codeString).isEmpty) {
          codes.add(
            PaymentCode.fromPaymentCode(
              codeString,
              networkType: networkType,
            ),
          );
        }
      } else {
        // otherwise we need to un blind the code
        final unBlinded = await unBlindedPaymentCodeFromTransaction(
          transaction: tx,
        );
        if (unBlinded != null &&
            codes.where((e) => e.toString() == unBlinded.toString()).isEmpty) {
          codes.add(unBlinded);
        }

        final unBlindedBad = await unBlindedPaymentCodeFromTransactionBad(
          transaction: tx,
        );
        if (unBlindedBad != null &&
            codes
                .where((e) => e.toString() == unBlindedBad.toString())
                .isEmpty) {
          codes.add(unBlindedBad);
        }
      }
    }

    return codes;
  }

  Future<void> checkForNotificationTransactionsTo(
      Set<String> otherCodeStrings) async {
    final sentNotificationTransactions = await mainDB
        .getTransactions(walletId)
        .filter()
        .subTypeEqualTo(TransactionSubType.bip47Notification)
        .and()
        .typeEqualTo(TransactionType.outgoing)
        .findAll();

    final List<PaymentCode> codes = [];
    for (final codeString in otherCodeStrings) {
      codes.add(
          PaymentCode.fromPaymentCode(codeString, networkType: networkType));
    }

    for (final tx in sentNotificationTransactions) {
      if (tx.address.value != null && tx.address.value!.otherData == null) {
        final oldAddress =
            await mainDB.getAddress(walletId, tx.address.value!.value);
        for (final code in codes) {
          final notificationAddress = code.notificationAddressP2PKH();
          if (notificationAddress == oldAddress!.value) {
            final address = Address(
              walletId: walletId,
              value: notificationAddress,
              publicKey: [],
              derivationIndex: 0,
              derivationPath: oldAddress.derivationPath,
              type: oldAddress.type,
              subType: AddressSubType.paynymNotification,
              otherData: await storeCode(code.toString()),
            );
            await mainDB.updateAddress(oldAddress, address);
          }
        }
      }
    }
  }

  Future<void> restoreAllHistory({
    required int maxUnusedAddressGap,
    required int maxNumberOfIndexesToCheck,
    required Set<String> paymentCodeStrings,
  }) async {
    final codes = await getAllPaymentCodesFromNotificationTransactions();
    final List<PaymentCode> extraCodes = [];
    for (final codeString in paymentCodeStrings) {
      if (codes.where((e) => e.toString() == codeString).isEmpty) {
        final extraCode = PaymentCode.fromPaymentCode(
          codeString,
          networkType: networkType,
        );
        if (extraCode.isValid()) {
          extraCodes.add(extraCode);
        }
      }
    }

    codes.addAll(extraCodes);

    final List<Future<void>> futures = [];
    for (final code in codes) {
      futures.add(
        restoreHistoryWith(
          other: code,
          maxUnusedAddressGap: maxUnusedAddressGap,
          maxNumberOfIndexesToCheck: maxNumberOfIndexesToCheck,
          checkSegwitAsWell: code.isSegWitEnabled(),
        ),
      );
    }

    await Future.wait(futures);
  }

  Future<void> restoreHistoryWith({
    required PaymentCode other,
    required bool checkSegwitAsWell,
    required int maxUnusedAddressGap,
    required int maxNumberOfIndexesToCheck,
  }) async {
    // https://en.bitcoin.it/wiki/BIP_0047#Path_levels
    const maxCount = 2147483647;
    assert(maxNumberOfIndexesToCheck < maxCount);

    final mySendBip32Node = await deriveNotificationBip32Node();

    List<Address> addresses = [];
    int receivingGapCounter = 0;
    int outgoingGapCounter = 0;

    // non segwit receiving
    for (int i = 0;
        i < maxNumberOfIndexesToCheck &&
            receivingGapCounter < maxUnusedAddressGap;
        i++) {
      if (receivingGapCounter < maxUnusedAddressGap) {
        final address = await _generatePaynymReceivingAddress(
          sender: other,
          index: i,
          generateSegwitAddress: false,
        );

        addresses.add(address);

        final count = await fetchTxCount(
          addressScriptHash: cryptoCurrency.addressToScriptHash(
            address: address.value,
          ),
        );

        if (count > 0) {
          receivingGapCounter = 0;
        } else {
          receivingGapCounter++;
        }
      }
    }

    // non segwit sends
    for (int i = 0;
        i < maxNumberOfIndexesToCheck &&
            outgoingGapCounter < maxUnusedAddressGap;
        i++) {
      if (outgoingGapCounter < maxUnusedAddressGap) {
        final address = await _generatePaynymSendAddress(
          other: other,
          index: i,
          generateSegwitAddress: false,
          mySendBip32Node: mySendBip32Node,
        );

        addresses.add(address);

        final count = await fetchTxCount(
          addressScriptHash: cryptoCurrency.addressToScriptHash(
            address: address.value,
          ),
        );

        if (count > 0) {
          outgoingGapCounter = 0;
        } else {
          outgoingGapCounter++;
        }
      }
    }

    if (checkSegwitAsWell) {
      int receivingGapCounterSegwit = 0;
      int outgoingGapCounterSegwit = 0;
      // segwit receiving
      for (int i = 0;
          i < maxNumberOfIndexesToCheck &&
              receivingGapCounterSegwit < maxUnusedAddressGap;
          i++) {
        if (receivingGapCounterSegwit < maxUnusedAddressGap) {
          final address = await _generatePaynymReceivingAddress(
            sender: other,
            index: i,
            generateSegwitAddress: true,
          );

          addresses.add(address);

          final count = await fetchTxCount(
            addressScriptHash: cryptoCurrency.addressToScriptHash(
              address: address.value,
            ),
          );

          if (count > 0) {
            receivingGapCounterSegwit = 0;
          } else {
            receivingGapCounterSegwit++;
          }
        }
      }

      // segwit sends
      for (int i = 0;
          i < maxNumberOfIndexesToCheck &&
              outgoingGapCounterSegwit < maxUnusedAddressGap;
          i++) {
        if (outgoingGapCounterSegwit < maxUnusedAddressGap) {
          final address = await _generatePaynymSendAddress(
            other: other,
            index: i,
            generateSegwitAddress: true,
            mySendBip32Node: mySendBip32Node,
          );

          addresses.add(address);

          final count = await fetchTxCount(
            addressScriptHash: cryptoCurrency.addressToScriptHash(
              address: address.value,
            ),
          );

          if (count > 0) {
            outgoingGapCounterSegwit = 0;
          } else {
            outgoingGapCounterSegwit++;
          }
        }
      }
    }
    await mainDB.updateOrPutAddresses(addresses);
  }

  Future<Address> getMyNotificationAddress() async {
    final storedAddress = await mainDB
        .getAddresses(walletId)
        .filter()
        .subTypeEqualTo(AddressSubType.paynymNotification)
        .and()
        .typeEqualTo(AddressType.p2pkh)
        .and()
        .not()
        .typeEqualTo(AddressType.nonWallet)
        .findFirst();

    if (storedAddress != null) {
      return storedAddress;
    } else {
      final root = await _getRootNode();
      final node = root.derivePath(
        _basePaynymDerivePath(
          testnet: info.coin.isTestNet,
        ),
      );
      final paymentCode = PaymentCode.fromBip32Node(
        node,
        networkType: networkType,
        shouldSetSegwitBit: false,
      );

      final data = btc_dart.PaymentData(
        pubkey: paymentCode.notificationPublicKey(),
      );

      final addressString = btc_dart
          .P2PKH(
            data: data,
            network: networkType,
          )
          .data
          .address!;

      Address address = Address(
        walletId: walletId,
        value: addressString,
        publicKey: paymentCode.getPubKey(),
        derivationIndex: 0,
        derivationPath: DerivationPath()
          ..value = _notificationDerivationPath(
            testnet: info.coin.isTestNet,
          ),
        type: AddressType.p2pkh,
        subType: AddressSubType.paynymNotification,
        otherData: await storeCode(paymentCode.toString()),
      );

      // check against possible race condition. Ff this function was called
      // multiple times an address could've been saved after the check at the
      // beginning to see if there already was notification address. This would
      // lead to a Unique Index violation  error
      await mainDB.isar.writeTxn(() async {
        final storedAddress = await mainDB
            .getAddresses(walletId)
            .filter()
            .subTypeEqualTo(AddressSubType.paynymNotification)
            .and()
            .typeEqualTo(AddressType.p2pkh)
            .and()
            .not()
            .typeEqualTo(AddressType.nonWallet)
            .findFirst();

        if (storedAddress == null) {
          await mainDB.isar.addresses.put(address);
        } else {
          address = storedAddress;
        }
      });

      return address;
    }
  }

  /// look up a key that corresponds to a payment code string
  Future<List<String>> lookupKey(String paymentCodeString) async {
    final keys = (await secureStorageInterface.keys).where(
      (e) => e.startsWith(kPCodeKeyPrefix),
    );
    final List<String> result = [];
    for (final key in keys) {
      final value = await secureStorageInterface.read(key: key);
      if (value == paymentCodeString) {
        result.add(key);
      }
    }
    return result;
  }

  /// fetch a payment code string
  Future<String?> paymentCodeStringByKey(String key) async {
    final value = await secureStorageInterface.read(key: key);
    return value;
  }

  /// store payment code string and return the generated key used
  Future<String> storeCode(String paymentCodeString) async {
    final key = _generateKey();
    await secureStorageInterface.write(key: key, value: paymentCodeString);
    return key;
  }

  /// generate a new payment code string storage key
  String _generateKey() {
    final bytes = _randomBytes(24);
    return "$kPCodeKeyPrefix${bytes.toHex}";
  }

  // https://github.com/AaronFeickert/stack_wallet_backup/blob/master/lib/secure_storage.dart#L307-L311
  /// Generate cryptographically-secure random bytes
  Uint8List _randomBytes(int n) {
    final Random rng = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(n, (_) => rng.nextInt(0xFF + 1)));
  }
}
