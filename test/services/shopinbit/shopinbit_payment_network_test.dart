import 'package:flutter_test/flutter_test.dart';
import 'package:stackwallet/pages/shopinbit/shopinbit_payment_shared.dart';

void main() {
  test('labels Ethereum USDT as ERC20', () {
    expect(
      shopInBitPaymentMethodLabel(
        ticker: 'USDT',
        paymentUri: 'ethereum:0x1111111111111111111111111111111111111111',
      ),
      'USDT (ERC20)',
    );
  });

  test('labels Tron USDT as TRC20', () {
    expect(
      shopInBitPaymentMethodLabel(
        ticker: 'USDT',
        paymentUri: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8',
      ),
      'USDT (TRC20)',
    );
  });

  test('does not guess an unknown USDT network', () {
    expect(
      shopInBitPaymentMethodLabel(
        ticker: 'USDT',
        paymentUri: 'unknown-address',
      ),
      'USDT (network unknown)',
    );
  });

  test('leaves non-USDT tickers unchanged', () {
    expect(
      shopInBitPaymentMethodLabel(ticker: 'xmr', paymentUri: 'address'),
      'XMR',
    );
  });
}
