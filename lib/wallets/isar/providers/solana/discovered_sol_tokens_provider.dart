/*
 * This file is part of Stack Wallet.
 *
 * Copyright (c) 2025 Cypher Stack
 * All Rights Reserved.
 * The code is distributed under GPLv3 license, see LICENSE file for details.
 *
 */

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/isar/models/solana/sol_contract.dart';
import '../../../../providers/global/wallets_provider.dart';
import '../../../../services/solana/solana_token_api.dart';
import '../../../../utilities/logger.dart';
import '../../../../wallets/wallet/impl/solana_wallet.dart';

/// Discovers the SPL tokens held by a wallet and resolves their metadata.
///
/// Returns a list of [SolContract]s for the mints found in the wallet's token
/// accounts. Metadata is fetched per mint, falling back to placeholder values
/// when it cannot be resolved.
final pDiscoveredSolanaTokens =
    FutureProvider.family<
      List<SolContract>,
      ({String walletId, String walletAddress})
    >((ref, params) async {
      final wallet = ref.read(pWallets).getWallet(params.walletId);
      if (wallet is! SolanaWallet) {
        throw Exception("Wallet ${params.walletId} is not a Solana wallet");
      }

      final rpcClient = wallet.getRpcClient();
      if (rpcClient == null) {
        throw Exception("RPC client not available for ${params.walletId}");
      }

      final api = SolanaTokenAPI();
      api.initializeRpcClient(rpcClient);

      final mintResponse = await api.discoverTokensForWallet(
        walletAddress: params.walletAddress,
      );

      if (!mintResponse.isSuccess || mintResponse.value == null) {
        throw mintResponse.exception ??
            Exception("Token discovery failed for ${params.walletId}");
      }

      final mints = mintResponse.value!;
      Logging.instance.i(
        "Discovered ${mints.length} SPL token mint(s) for ${params.walletId}",
      );

      final tokens = await Future.wait(
        mints.map((discovered) async {
          final mint = discovered.mint;
          final metadataResponse = await api.fetchTokenMetadataByMint(mint);
          final metadata = metadataResponse.value;

          // Decimals come from on-chain data: the parsed token account's
          // tokenAmount.decimals (or the mint account as a fallback). Prefer
          // that over any value in resolved metadata.
          final decimals =
              discovered.decimals ??
              int.tryParse(metadata?["decimals"]?.toString() ?? "");

          return SolContract(
            address: mint,
            name: metadata?["name"] as String? ?? _placeholderName(mint),
            symbol: metadata?["symbol"] as String? ?? _placeholderSymbol(mint),
            decimals: decimals ?? 0,
            logoUri: metadata?["logoUri"] as String?,
          );
        }),
      );

      return tokens;
    });

/// Build a short, human readable placeholder name from a mint address when no
/// metadata could be resolved.
String _placeholderName(String mint) {
  if (mint.length <= 10) {
    return "Token $mint";
  }
  return "Token ${mint.substring(0, 4)}...${mint.substring(mint.length - 4)}";
}

/// Build a short placeholder symbol from a mint address when no metadata could
/// be resolved.
String _placeholderSymbol(String mint) {
  if (mint.length <= 4) {
    return mint.toUpperCase();
  }
  return mint.substring(0, 4).toUpperCase();
}
