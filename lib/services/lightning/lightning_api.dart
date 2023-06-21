import 'dart:convert';

import 'package:stackwallet/utilities/default_nodes.dart';
import 'package:ldk_node/ldk_node.dart' as ldk;
import 'package:stackwallet/utilities/logger.dart';

abstract class LightningApi {
  static String get esploraUrl => DefaultNodes.esploraUrl;
  late ldk.Node node;



  Future<ldk.Config> initLdkConfig(
      ldk.SocketAddr address,
      String walletName) async {

    final nodePath = "$walletName/ldk_cache";
    final config = ldk.Config(
        storageDirPath: nodePath,
        esploraServerUrl: esploraUrl,
        network: ldk.Network.Testnet,
        listeningAddress: address,
        defaultCltvExpiryDelta: 144);
    return config;
  }

  void initNode(
      String walletMnemonic,
      String walletName
      ) async {
    //For an existing wallet this should already exist and be stored locally
    //TODO - UPDATE PATH HERE TO BE THE WALLET PATH
    //VERIFY WHAT SOCKET ADDRESS WILL BE WHEN NOT TESTING

    final config = await initLdkConfig(
        const ldk.SocketAddr(ip: "0.0.0.0", port: 8077), walletName);

    ldk.WalletEntropySource entropySource = ldk.WalletEntropySource.bip39Mnemonic(mnemonic: walletMnemonic);
    ldk.Builder builder = ldk.Builder.fromConfig(config: config, entropySource: entropySource);
    node = await builder.build();
    await node.start();
  }


  void syncNode() async {
    await node.syncWallets();
  }

  Future<String> getNodeBalances() async {
    try {
      final balances = await node.onChainBalance();
      return jsonEncode({
        "immature": balances.immature,
        "trusted_pending": balances.trustedPending,
        "untrusted_pending": balances.untrustedPending,
        "confirmed": balances.confirmed
      });
    } catch (e, s) {
      Logging.instance
          .log("LND ERROR::Error getting balances: $e,\n$s", level: LogLevel.Error);
      rethrow;
    }

  }

  Future<String> getChannelList() async {
    try {
      final res = await node.listChannels();

      Map<String, dynamic> channelData = {};
      if (res.isNotEmpty) {
        for (var item in res) {
          channelData["${item.channelId.hashCode}"] = {
            "channel_id": item.channelId.hashCode,
            "funding_txo": item.fundingTxo,
            "funding_txo_confirmations": item.confirmations,
            "funding_txo_required_confirmations": item.confirmationsRequired,
            "is_outbound": item.isOutbound,
            "is_channel_ready": item.isChannelReady,
            "is_channel_usable": item.isUsable,
            "outbound_capacity_msat": item.outboundCapacityMsat,
            "balance_msat": item.balanceMsat,
          };
        }
      } else {
        //TODO - Handle empty response
        return "NO CHANNELS";
      }
      return jsonEncode(channelData);

    } catch (e, s) {
      Logging.instance
          .log("LND ERROR::Error getting wallet channels: $e,\n$s", level: LogLevel.Error);
      rethrow;
    }
  }

  Future<List<ldk.PaymentDetails>> listPayments() async {
    final incoming = await node.listPaymentsWithFilter(paymentDirection: ldk.PaymentDirection.Inbound);
    final outgoing = await node.listPaymentsWithFilter(paymentDirection: ldk.PaymentDirection.Outbound);

    return incoming + outgoing;
  }

  void openChannel(
      String peerNodeIdHex,
      int channelAmountSats,
      ldk.SocketAddr address,
      int pushToCounterpartysat,
      ) async {
    try {

      ldk.PublicKey peerNodeId = ldk.PublicKey(keyHex: peerNodeIdHex);
      await node.connectOpenChannel(
          channelAmountSats: channelAmountSats,
          announceChannel: true,
          address: address,
          pushToCounterpartyMsat: pushToCounterpartysat,
          nodeId: peerNodeId);

    } catch (e, s) {
      Logging.instance
          .log("LND ERROR::Error Opening a new channel: $e,\n$s", level: LogLevel.Error);
      rethrow;
    }
  }

  void stop() async {
    try {
      await node.stop();
    } catch (e, s) {
      final nodeId = await node.nodeId();
      Logging.instance
          .log("LND ERROR::Error STOPPING NODE ${nodeId.keyHex}: $e,\n$s", level: LogLevel.Error);
    }
  }

  Future<String> createInvoice(int amountSats, String description, int expirySecs) async {
    try {
      final amountMsat = satoshiToMilliSatoshi(amountSats);
      final ldk.Invoice invoice = await node.receivePayment(
          amountMsat: amountMsat,
          description: description,
          expirySecs: expirySecs);

      return invoice.hex;
    } catch (e, s) {
      Logging.instance
          .log("LND ERROR::Could not send Invoice with error: $e,\n$s", level: LogLevel.Error);
      rethrow;
    }
  }

  int satoshiToMilliSatoshi(int satoshiAmount) {
    return satoshiAmount*1000;
  }

}