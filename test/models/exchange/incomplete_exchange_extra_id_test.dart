import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stackwallet/models/exchange/incomplete_exchange.dart';
import 'package:stackwallet/models/exchange/response_objects/estimate.dart';
import 'package:stackwallet/models/isar/exchange_cache/currency.dart';
import 'package:stackwallet/models/isar/exchange_cache/pair.dart';
import 'package:stackwallet/services/exchange/cyphergoat/cyphergoat_exchange.dart';
import 'package:stackwallet/utilities/enums/exchange_rate_type_enum.dart';

void main() {
  test('retains payout and refund memo or tag values', () {
    final send = _currency('XLM');
    final receive = _currency('XRP');
    final model = IncompleteExchangeModel(
      sendCurrency: send,
      receiveCurrency: receive,
      rateInfo: '1 XLM = 1 XRP',
      sendAmount: Decimal.one,
      receiveAmount: Decimal.one,
      rateType: ExchangeRateType.estimated,
      reversed: false,
      walletInitiated: false,
    );

    model
      ..recipientExtraId = 'destination-tag-42'
      ..refundExtraId = 'refund-memo-7';

    expect(model.recipientExtraId, 'destination-tag-42');
    expect(model.refundExtraId, 'refund-memo-7');
  });

  test('CypherGoat rejects a destination tag it cannot forward', () async {
    final result = await CypherGoatExchange.instance.createTrade(
      from: 'btc',
      to: 'xrp',
      fromNetwork: 'btc',
      toNetwork: 'xrp',
      fixedRate: false,
      amount: Decimal.one,
      addressTo: 'destination',
      extraId: 'destination-tag-42',
      addressRefund: '',
      refundExtraId: '',
      estimate: Estimate(
        estimatedAmount: Decimal.one,
        fixedRate: false,
        reversed: false,
        rateId: '1',
        exchangeProvider: 'provider',
      ),
      reversed: false,
    );

    expect(result.value, isNull);
    expect(result.exception.toString(), contains('memo or tag'));
  });
}

Currency _currency(String ticker) => Currency(
  exchangeName: 'test',
  ticker: ticker,
  name: ticker,
  network: ticker.toLowerCase(),
  image: '',
  isFiat: false,
  rateType: SupportedRateType.estimated,
  isStackCoin: false,
  tokenContract: null,
);
