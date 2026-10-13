import 'package:flutter/services.dart';

/// Capitalizes word initials while preserving the rest of a person's spelling.
String capitalizeName(String text) => text.replaceAllMapped(
  RegExp(r'(^|\s)(\S)'),
  (match) => '${match[1]}${match[2]!.toUpperCase()}',
);

class NameInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final text = capitalizeName(newValue.text);
    return newValue.copyWith(
      text: text,
      selection: text.length == newValue.text.length
          ? newValue.selection
          : TextSelection.collapsed(offset: text.length),
    );
  }
}
