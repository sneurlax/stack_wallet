/* 
 * This file is part of Stack Wallet.
 * 
 * Copyright (c) 2023 Cypher Stack
 * All Rights Reserved.
 * The code is distributed under GPLv3 license, see LICENSE file for details.
 * Generated by Cypher Stack on 2023-05-26
 *
 */

import 'package:flutter/material.dart';
import 'package:stackwallet/pages/add_wallet_views/add_token_view/sub_widgets/add_custom_token_selector.dart';
import 'package:stackwallet/pages/add_wallet_views/add_token_view/sub_widgets/add_token_list_element.dart';
import 'package:stackwallet/widgets/conditional_parent.dart';

class AddTokenList extends StatelessWidget {
  const AddTokenList({
    Key? key,
    required this.walletId,
    required this.items,
    required this.addFunction,
  }) : super(key: key);

  final String walletId;
  final List<AddTokenListElementData> items;
  final VoidCallback? addFunction;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      primary: false,
      itemCount: items.length,
      itemBuilder: (ctx, index) {
        return ConditionalParent(
          condition: index == items.length - 1 && addFunction != null,
          builder: (child) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              AddCustomTokenSelector(
                addFunction: addFunction!,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: AddTokenListElement(
              data: items[index],
            ),
          ),
        );
      },
    );
  }
}
