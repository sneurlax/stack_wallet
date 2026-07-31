import '../../models/shopinbit/shopinbit_enums.dart';
import '../../services/shopinbit/src/api_exception.dart';
import '../../services/shopinbit/src/api_response.dart';
import '../../services/shopinbit/src/models/payment.dart';

/// Resolved delivery metadata for an offer. Invalid server/ticket data is
/// represented by [error] instead of throwing while a view is being built.
class ShopInBitDeliveryLocation {
  const ShopInBitDeliveryLocation._({
    required this.countryIso,
    required this.countryLabel,
    required this.requiresState,
    required this.state,
    required this.error,
  });

  factory ShopInBitDeliveryLocation.resolve({
    required String countryIso,
    required ShopInBitCategory category,
    required String? firstMessageContent,
    required List<Map<String, dynamic>> countries,
  }) {
    String? countryLabel;
    for (final country in countries) {
      if (country['iso'] == countryIso && country['label'] is String) {
        countryLabel = country['label'] as String;
        break;
      }
    }

    final requiresState =
        category != ShopInBitCategory.travel &&
        shopInBitAddressRequiresState(countryIso);
    final state = requiresState ? _extractState(firstMessageContent) : null;

    final String? error;
    if (countryLabel == null) {
      error = 'The delivery country is not available.';
    } else if (requiresState && state == null) {
      error = 'The delivery state or province is missing.';
    } else {
      error = null;
    }

    return ShopInBitDeliveryLocation._(
      countryIso: countryIso,
      countryLabel: countryLabel,
      requiresState: requiresState,
      state: state,
      error: error,
    );
  }

  final String countryIso;
  final String? countryLabel;
  final bool requiresState;
  final String? state;
  final String? error;

  bool get isValid => error == null;
}

bool shopInBitAddressRequiresState(String? countryIso) =>
    countryIso == 'US' || countryIso == 'CA';

String? _extractState(String? content) {
  if (content == null) return null;
  final pattern = RegExp(
    r'^(?:Delivery state|State):\s*(.+)$',
    caseSensitive: false,
  );
  for (final line in content.split('\n')) {
    final match = pattern.firstMatch(line.trim());
    final value = match?.group(1)?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

/// Submits the address before creating or regenerating a payment invoice.
/// Payment is never attempted after an address failure.
Future<ApiResponse<PaymentInfo>> submitShopInBitCheckout({
  required bool termsAccepted,
  required Future<ApiResponse<Map<String, dynamic>>> Function() submitAddress,
  required Future<PaymentInfo?> Function() createPayment,
}) async {
  if (!termsAccepted) {
    return ApiResponse(
      exception: ApiException('Terms & Conditions consent is required'),
    );
  }
  try {
    final addressResponse = await submitAddress();
    if (addressResponse.hasError) {
      return ApiResponse(exception: addressResponse.exception);
    }

    final payment = await createPayment();
    if (payment == null) {
      return ApiResponse(
        exception: ApiException('Unable to create a payment invoice'),
      );
    }
    return ApiResponse(value: payment);
  } on ApiException catch (e) {
    return ApiResponse(exception: e);
  } catch (e) {
    return ApiResponse(exception: ApiException.network(e));
  }
}
