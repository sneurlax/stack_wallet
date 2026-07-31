import 'package:flutter_test/flutter_test.dart';
import 'package:stackwallet/services/shopinbit/shopinbit_service.dart';

void main() {
  test('best-effort refresh reports errors without rethrowing', () async {
    Object? reportedError;

    await runShopInBitRefreshBestEffort(
      () => Future<void>.error(StateError('network unavailable')),
      onError: (error, _) => reportedError = error,
    );

    expect(reportedError, isA<StateError>());
  });
}
