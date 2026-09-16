import 'package:arbiter_mock_server/ui/screens/share/nearby_share_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  // Regression: a bare QrImageView inside a scrollable AlertDialog threw
  // "LayoutBuilder does not support returning intrinsic dimensions" every
  // frame, so the share dialog rendered black.
  testWidgets('share QR renders inside a scrollable AlertDialog', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: AlertDialog(
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [ShareCodeQr(code: 'K7Q4MXP2A'), Text('K7Q-4MX-P2A')],
          ),
          actions: [TextButton(onPressed: null, child: Text('Close'))],
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(QrImageView), findsOneWidget);
  });
}
