import 'package:flutter_test/flutter_test.dart';
import 'package:stackwallet/pages/masternodes/masternode_fee_plan.dart';
import 'package:stackwallet/utilities/amount/amount.dart';

void main() {
  test('Spark fee is required from balance but not added to send amount', () {
    final plan = planMasternodeFeeUnshield(
      consolidationFee: _amount(10),
      transparentBuffer: _amount(2),
      sparkFee: _amount(3),
    );

    expect(plan.amountToUnshield.raw, BigInt.from(12));
    expect(plan.requiredSparkBalance.raw, BigInt.from(15));
  });
}

Amount _amount(int raw) =>
    Amount(rawValue: BigInt.from(raw), fractionDigits: 8);
