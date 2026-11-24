import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/widgets/app_title.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool devMode}) {
    return tester.pumpWidget(MaterialApp(home: Scaffold(body: AppTitle(devMode: devMode))));
  }

  testWidgets('ordinary users see only the name', (tester) async {
    await pump(tester, devMode: false);
    expect(find.text('My Tour'), findsOneWidget);
    expect(find.text('DEV'), findsNothing);
  });

  testWidgets('developer mode is written in red on the title', (tester) async {
    await pump(tester, devMode: true);
    final badge = tester.widget<Text>(find.text('DEV'));
    expect(badge.style!.color, Colors.red);
    expect(badge.style!.fontWeight, FontWeight.bold);
  });
}
