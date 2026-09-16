import 'package:arbiter_mock_server/ui/screens/share/share_code_input_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _at(String text, [int? caret]) =>
    TextEditingValue(text: text, selection: TextSelection.collapsed(offset: caret ?? text.length));

/// Simulates typing [input] one character at a time at the end.
TextEditingValue _type(String input) {
  final formatter = ShareCodeInputFormatter();
  var value = _at('');
  for (final ch in input.split('')) {
    value = formatter.formatEditUpdate(value, _at(value.text + ch));
  }
  return value;
}

void main() {
  final formatter = ShareCodeInputFormatter();

  test('inserts hyphens and uppercases while typing', () {
    expect(_type('k7q').text, 'K7Q');
    expect(_type('k7q4').text, 'K7Q-4');
    expect(_type('k7q4mxp2a').text, 'K7Q-4MX-P2A');
    expect(_type('k7q4mxp2a').selection.extentOffset, 'K7Q-4MX-P2A'.length);
  });

  test('caps at 9 code characters and normalizes pasted text', () {
    expect(_type('k7q4mxp2azzz').text, 'K7Q-4MX-P2A');
    final pasted = formatter.formatEditUpdate(_at(''), _at(' k7q 4mx-p2a '));
    expect(pasted.text, 'K7Q-4MX-P2A');
  });

  test('backspace over a hyphen deletes the character before it', () {
    // "K7Q-4" with caret at end → backspace "4" → "K7Q" (no dangling hyphen).
    expect(formatter.formatEditUpdate(_at('K7Q-4'), _at('K7Q-')).text, 'K7Q');
    // Caret just after the hyphen in "K7Q-4MX": deleting the hyphen removes "Q".
    final result = formatter.formatEditUpdate(_at('K7Q-4MX', 4), _at('K7Q4MX', 3));
    expect(result.text, 'K74-MX');
    expect(result.selection.extentOffset, 2);
  });

  test('IP addresses pass through untouched', () {
    final value = _at('10.21.178.27:47778');
    expect(formatter.formatEditUpdate(_at('10.21.178.27:4777'), value), value);
    expect(_type('192.168.1.20').text, '192.168.1.20');
  });
}
