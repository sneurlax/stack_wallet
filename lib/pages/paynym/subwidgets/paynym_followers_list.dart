import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stackwallet/pages/paynym/subwidgets/paynym_card_button.dart';
import 'package:stackwallet/providers/wallet/my_paynym_account_state_provider.dart';
import 'package:stackwallet/utilities/constants.dart';
import 'package:stackwallet/utilities/text_styles.dart';
import 'package:stackwallet/utilities/theme/stack_colors.dart';
import 'package:stackwallet/utilities/util.dart';
import 'package:stackwallet/widgets/rounded_white_container.dart';

class PaynymFollowersList extends ConsumerStatefulWidget {
  const PaynymFollowersList({
    Key? key,
    required this.walletId,
  }) : super(key: key);

  final String walletId;

  @override
  ConsumerState<PaynymFollowersList> createState() =>
      _PaynymFollowersListState();
}

class _PaynymFollowersListState extends ConsumerState<PaynymFollowersList> {
  final isDesktop = Util.isDesktop;

  BorderRadius get _borderRadiusFirst {
    return BorderRadius.only(
      topLeft: Radius.circular(
        Constants.size.circularBorderRadius,
      ),
      topRight: Radius.circular(
        Constants.size.circularBorderRadius,
      ),
    );
  }

  BorderRadius get _borderRadiusLast {
    return BorderRadius.only(
      bottomLeft: Radius.circular(
        Constants.size.circularBorderRadius,
      ),
      bottomRight: Radius.circular(
        Constants.size.circularBorderRadius,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final followers =
        ref.watch(myPaynymAccountStateProvider.state).state?.followers;
    final count = followers?.length ?? 0;

    return ListView.separated(
      itemCount: max(count, 1),
      separatorBuilder: (BuildContext context, int index) => Container(
        height: 1.5,
        color: Colors.transparent,
      ),
      itemBuilder: (BuildContext context, int index) {
        if (count == 0) {
          return RoundedWhiteContainer(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Your PayNym followers will appear here",
                  style: isDesktop
                      ? STextStyles.desktopTextExtraExtraSmall(context)
                          .copyWith(
                          color: Theme.of(context)
                              .extension<StackColors>()!
                              .textSubtitle1,
                        )
                      : STextStyles.label(context),
                ),
              ],
            ),
          );
        } else if (count == 1) {
          return RoundedWhiteContainer(
            padding: const EdgeInsets.all(0),
            child: PaynymCardButton(
              walletId: widget.walletId,
              accountLite: followers![0],
            ),
          );
        } else {
          BorderRadius? borderRadius;
          if (index == 0) {
            borderRadius = _borderRadiusFirst;
          } else if (index == count - 1) {
            borderRadius = _borderRadiusLast;
          }

          return Container(
            key: Key("paynymCardKey_${followers![index].nymId}"),
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: Theme.of(context).extension<StackColors>()!.popupBG,
            ),
            child: PaynymCardButton(
              walletId: widget.walletId,
              accountLite: followers[index],
            ),
          );
        }
      },
    );
  }
}