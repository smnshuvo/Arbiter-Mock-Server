import 'package:arbiter_mock_server/domain/entities/network_condition.dart';
import 'package:arbiter_mock_server/ui/screens/endpoint_editor/widgets/network_condition_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    required NetworkCondition value,
    required ValueChanged<NetworkCondition> onChanged,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: NetworkConditionField(value: value, onChanged: onChanged),
            ),
          ),
        ),
      );

  testWidgets('shows the current condition label', (tester) async {
    await tester.pumpWidget(
        host(value: NetworkCondition.threeG, onChanged: (_) {}));
    expect(find.text('3G'), findsOneWidget);
  });

  testWidgets('defaults render the no-throttling label', (tester) async {
    await tester.pumpWidget(
        host(value: NetworkCondition.none, onChanged: (_) {}));
    expect(find.text('No throttling'), findsOneWidget);
  });

  testWidgets('opening the menu lists every condition the user asked for',
      (tester) async {
    await tester.pumpWidget(
        host(value: NetworkCondition.none, onChanged: (_) {}));

    await tester.tap(find.byType(NetworkConditionField));
    await tester.pumpAndSettle();

    for (final label in [
      'GPRS',
      'EDGE',
      '3G',
      '4G',
      '5G',
      'Unstable 2G',
    ]) {
      expect(find.text(label), findsWidgets, reason: '$label should be offered');
    }
  });

  testWidgets('picking a condition reports it back', (tester) async {
    NetworkCondition? picked;
    await tester.pumpWidget(
        host(value: NetworkCondition.none, onChanged: (v) => picked = v));

    await tester.tap(find.byType(NetworkConditionField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unstable 2G').last);
    await tester.pumpAndSettle();

    expect(picked, NetworkCondition.unstable2G);
  });

  testWidgets('the menu describes each condition', (tester) async {
    await tester.pumpWidget(
        host(value: NetworkCondition.none, onChanged: (_) {}));

    await tester.tap(find.byType(NetworkConditionField));
    await tester.pumpAndSettle();

    expect(find.text('50 kbps · 500 ms'), findsOneWidget);
    expect(find.text('40 kbps · 650 ms · ~25% time out'), findsOneWidget);
  });
}
