import 'package:flutter_test/flutter_test.dart';
import 'package:stackwallet/models/shopinbit/shopinbit_enums.dart';
import 'package:stackwallet/pages/shopinbit/shopinbit_checkout.dart';
import 'package:stackwallet/services/shopinbit/src/api_exception.dart';
import 'package:stackwallet/services/shopinbit/src/api_response.dart';
import 'package:stackwallet/services/shopinbit/src/models/payment.dart';

void main() {
  group('ShopInBitDeliveryLocation', () {
    const countries = <Map<String, dynamic>>[
      {'iso': 'US', 'label': 'United States'},
      {'iso': 'CA', 'label': 'Canada'},
      {'iso': 'DE', 'label': 'Germany'},
    ];

    test('reports a missing required state without throwing', () {
      final location = ShopInBitDeliveryLocation.resolve(
        countryIso: 'US',
        category: ShopInBitCategory.concierge,
        firstMessageContent: 'Request without a state',
        countries: countries,
      );

      expect(location.requiresState, isTrue);
      expect(location.state, isNull);
      expect(location.isValid, isFalse);
      expect(location.error, contains('state'));
    });

    test('extracts a required province from the ticket message', () {
      final location = ShopInBitDeliveryLocation.resolve(
        countryIso: 'CA',
        category: ShopInBitCategory.concierge,
        firstMessageContent: 'Delivery state: ON\nDetails: laptop',
        countries: countries,
      );

      expect(location.countryLabel, 'Canada');
      expect(location.state, 'ON');
      expect(location.isValid, isTrue);
    });

    test('reports an unknown delivery country without throwing', () {
      final location = ShopInBitDeliveryLocation.resolve(
        countryIso: 'ZZ',
        category: ShopInBitCategory.concierge,
        firstMessageContent: null,
        countries: countries,
      );

      expect(location.isValid, isFalse);
      expect(location.error, contains('country'));
    });

    test('billing state requirements are independent by country', () {
      expect(shopInBitAddressRequiresState('US'), isTrue);
      expect(shopInBitAddressRequiresState('CA'), isTrue);
      expect(shopInBitAddressRequiresState('DE'), isFalse);
      expect(shopInBitAddressRequiresState(null), isFalse);
    });
  });

  test('does not create payment when address submission fails', () async {
    var paymentCalls = 0;
    final result = await submitShopInBitCheckout(
      termsAccepted: true,
      submitAddress: () async => ApiResponse(
        exception: ApiException('invalid address', statusCode: 422),
      ),
      createPayment: () async {
        paymentCalls++;
        return PaymentInfo(
          status: 'ready_to_pay',
          customerPrice: '1',
          partnerPrice: '1',
          vatRate: null,
          currency: 'EUR',
          paymentLinks: const {},
        );
      },
    );

    expect(result.hasError, isTrue);
    expect(result.exception?.statusCode, 422);
    expect(paymentCalls, 0);
  });

  test('does not submit an address or payment without terms consent', () async {
    var addressCalls = 0;
    var paymentCalls = 0;
    final result = await submitShopInBitCheckout(
      termsAccepted: false,
      submitAddress: () async {
        addressCalls++;
        return ApiResponse(value: <String, dynamic>{});
      },
      createPayment: () async {
        paymentCalls++;
        return null;
      },
    );

    expect(result.hasError, isTrue);
    expect(result.exception?.message, contains('Terms'));
    expect(addressCalls, 0);
    expect(paymentCalls, 0);
  });
}
