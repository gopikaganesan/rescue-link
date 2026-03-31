import 'package:flutter_test/flutter_test.dart';
import 'package:rescue_link/widgets/sos_button.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('SOS button renders and responds to tap', (WidgetTester tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SOSButton(
              onPressed: () {
                tapped = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('SOS'), findsOneWidget);
    await tester.tap(find.byType(SOSButton));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });
}
