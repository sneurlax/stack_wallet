import '../../utilities/amount/amount.dart';

typedef MasternodeFeeUnshieldPlan = ({
  Amount amountToUnshield,
  Amount requiredSparkBalance,
});

/// Plans the Spark-to-transparent transfer used to fund collateral creation.
///
/// The Spark fee must be available in the private balance, but it is paid by
/// the transaction and must not also be included in the recipient amount.
MasternodeFeeUnshieldPlan planMasternodeFeeUnshield({
  required Amount consolidationFee,
  required Amount transparentBuffer,
  required Amount sparkFee,
}) {
  final amountToUnshield = consolidationFee + transparentBuffer;
  return (
    amountToUnshield: amountToUnshield,
    requiredSparkBalance: amountToUnshield + sparkFee,
  );
}
