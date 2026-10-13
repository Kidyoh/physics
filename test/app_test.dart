import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactile/src/app.dart';

void main() {
  testWidgets('switches between the three modes and paints', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TactileApp());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Sand'), findsWidgets);
    for (final label in ['Water', 'Fire', 'Oil']) {
      expect(find.text(label), findsOneWidget);
    }

    // Paint a stroke on the sand canvas.
    final gesture = await tester.startGesture(const Offset(180, 400));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(5, 3));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();

    await tester.tap(find.byIcon(Icons.waves));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Fluid'), findsOneWidget);
    expect(find.text('Rainbow'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.curtains));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tear'), findsOneWidget);
    await tester.tap(find.text('Tear'));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  testWidgets('top bar fits on a narrow 320dp phone', (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const TactileApp());
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });
}
