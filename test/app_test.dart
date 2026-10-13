import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactile/src/app.dart';
import 'package:tactile/src/ui/intro.dart';

void main() {
  void phone(WidgetTester tester, Size physical, double ratio) {
    tester.view.physicalSize = physical;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
  }

  testWidgets('switches between the three modes and paints', (tester) async {
    phone(tester, const Size(1080, 2340), 3);
    await tester.pumpWidget(const TactileApp(showIntro: false));
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

    await tester.tap(find.byIcon(Icons.water_drop_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Fluid'), findsOneWidget);
    expect(find.text('Rainbow'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.flag_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Tear'), findsOneWidget);
    await tester.tap(find.text('Tear'));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chrome fits on a narrow 320dp phone', (tester) async {
    phone(tester, const Size(640, 1136), 2);
    await tester.pumpWidget(const TactileApp(showIntro: false));
    await tester.pump(const Duration(milliseconds: 50));
    for (final icon in [Icons.water_drop_rounded, Icons.flag_rounded]) {
      await tester.tap(find.byIcon(icon));
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('intro builds the title out of grains and hands over', (tester) async {
    phone(tester, const Size(1080, 2340), 3);
    await tester.pumpWidget(const TactileApp());
    // Rasterising the title mask is real async engine work.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(find.byType(IntroOverlay), findsOneWidget);

    // Run the timeline to the end; the overlay removes itself.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(IntroOverlay), findsNothing);
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
