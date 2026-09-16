import 'package:flutter/services.dart';

/// Formats a share code as it's typed: uppercase, `K7Q-4MX-P2A` grouping with
/// hyphens inserted automatically, capped at 9 characters.
///
/// The same field also accepts a plain `ip:port`, so anything containing `.`
/// or `:` is passed through untouched. Backspacing over an auto-inserted
/// hyphen deletes the character before it, so the caret never gets stuck.
class ShareCodeInputFormatter extends TextInputFormatter {
  static const int _groupSize = 3;
  static const int _maxChars = 9;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.contains(RegExp(r'[.:]'))) return newValue;

    var text = newValue.text;
    var caret = newValue.selection.isValid ? newValue.selection.extentOffset : text.length;

    // A single backspace that only removed a hyphen: remove the char before it too.
    final deletedOne = oldValue.text.length - text.length == 1;
    if (deletedOne &&
        caret < oldValue.text.length &&
        oldValue.text[caret] == '-' &&
        caret > 0) {
      text = text.replaceRange(caret - 1, caret, '');
      caret -= 1;
    }

    // Count code characters before the caret, then rebuild with hyphens.
    final isCodeChar = RegExp(r'[A-Za-z0-9]');
    var charsBeforeCaret = 0;
    for (var i = 0; i < caret && i < text.length; i++) {
      if (isCodeChar.hasMatch(text[i])) charsBeforeCaret++;
    }
    final raw = text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final clipped = raw.length > _maxChars ? raw.substring(0, _maxChars) : raw;
    charsBeforeCaret = charsBeforeCaret.clamp(0, clipped.length);

    final formatted = StringBuffer();
    var newCaret = 0;
    for (var i = 0; i < clipped.length; i++) {
      if (i > 0 && i % _groupSize == 0) formatted.write('-');
      formatted.write(clipped[i]);
      if (i + 1 == charsBeforeCaret) newCaret = formatted.length;
    }
    if (charsBeforeCaret == 0) newCaret = 0;

    return TextEditingValue(
      text: formatted.toString(),
      selection: TextSelection.collapsed(offset: newCaret),
    );
  }
}
