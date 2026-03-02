import 'dart:math';

import 'package:flutter/services.dart';

import '../util.dart';
import 'amount_unit.dart';

class AmountInputFormatter extends TextInputFormatter {
  final int decimals;
  final String locale;
  final AmountUnit? unit;

  AmountInputFormatter({
    required this.decimals,
    required this.locale,
    this.unit,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // get number symbols for decimal place and group separator
    final numberSymbols = Util.getSymbolsFor(locale: locale);

    final decimalSeparator = numberSymbols?.DECIMAL_SEP ?? ".";
    final groupSeparator = numberSymbols?.GROUP_SEP ?? ",";

    // Detect paste: new text is significantly longer than old text.
    // Normalize pasted values that may use a different locale's separators.
    TextEditingValue valueToProcess = newValue;
    if (newValue.text.length - oldValue.text.length > 1) {
      String pasted = newValue.text;
      final hasDots = pasted.contains(".");
      final hasCommas = pasted.contains(",");

      if (hasDots && hasCommas) {
        // Both separators present: the last occurrence is the decimal sep.
        final lastDot = pasted.lastIndexOf(".");
        final lastComma = pasted.lastIndexOf(",");
        if (lastDot > lastComma) {
          // e.g. "1,234.56" — dot is decimal
          pasted = pasted.replaceAll(",", "");
          pasted = pasted.replaceFirst(".", decimalSeparator);
        } else {
          // e.g. "1.234,56" — comma is decimal
          pasted = pasted.replaceAll(".", "");
          pasted = pasted.replaceFirst(",", decimalSeparator);
        }
      } else if (hasDots && !hasCommas && decimalSeparator == ",") {
        // Locale expects "," as decimal but pasted value uses ".".
        // If there's exactly one ".", treat it as the decimal separator.
        if (".".allMatches(pasted).length == 1) {
          pasted = pasted.replaceFirst(".", decimalSeparator);
        } else {
          // Multiple dots: they are group separators, remove them.
          pasted = pasted.replaceAll(".", "");
        }
      } else if (hasCommas && !hasDots && decimalSeparator == ".") {
        // Locale expects "." as decimal but pasted value uses ",".
        // If there's exactly one ",", treat it as the decimal separator.
        if (",".allMatches(pasted).length == 1) {
          pasted = pasted.replaceFirst(",", decimalSeparator);
        } else {
          // Multiple commas: they are group separators, remove them.
          pasted = pasted.replaceAll(",", "");
        }
      }

      valueToProcess = TextEditingValue(
        text: pasted,
        selection: TextSelection.collapsed(offset: pasted.length),
      );
    }

    String newText = valueToProcess.text.replaceAll(groupSeparator, "");

    final selectionIndexFromTheRight =
        valueToProcess.text.length - valueToProcess.selection.end;

    String? fraction;
    if (newText.contains(decimalSeparator)) {
      final parts = newText.split(decimalSeparator);

      if (parts.length > 2) {
        return oldValue;
      }

      final fractionDigits =
          unit == null ? decimals : max(decimals - unit!.shift, 0);

      if (newText.startsWith(decimalSeparator)) {
        if (newText.length - 1 > fractionDigits) {
          newText = newText.substring(0, fractionDigits + 1);
        }

        return TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(
            offset: newText.length - selectionIndexFromTheRight,
          ),
        );
      }

      newText = parts.first;
      if (parts.length == 2) {
        fraction = parts.last;
      } else {
        fraction = "";
      }

      if (fraction.length > fractionDigits) {
        fraction = fraction.substring(0, fractionDigits);
      }
    }

    String newString;
    final val = BigInt.tryParse(newText);
    if (val == null || val < BigInt.one) {
      newString = newText;
    } else {
      // insert group separator
      final regex = RegExp(r'\B(?=(\d{3})+(?!\d))');
      newString = newText.replaceAllMapped(
        regex,
        (m) => "${m.group(0)}${numberSymbols?.GROUP_SEP ?? ","}",
      );
    }

    if (fraction != null) {
      newString += decimalSeparator;
      if (fraction.isNotEmpty) {
        newString += fraction;
      }
    }

    return TextEditingValue(
      text: newString,
      selection: TextSelection.collapsed(
        offset: newString.length - selectionIndexFromTheRight,
      ),
    );
  }
}
