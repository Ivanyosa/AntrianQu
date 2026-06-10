import 'package:antrianqai/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders AntrianQAI brand header', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: Center(child: BrandHeader())),
      ),
    );

    expect(find.text('AntrianQAI'), findsOneWidget);
    expect(find.text('Predictable, fast, and reliable'), findsOneWidget);
  });
}
