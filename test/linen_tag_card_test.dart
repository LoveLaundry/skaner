import 'dart:convert';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_mobi/features/linen/linen_tag_card.dart';
import 'package:love_mobi/ui/theme.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  const tag = 'BSG-A0001XL';

  Future<void> pumpTag(WidgetTester tester, Widget card) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.build(AppTheme.light, AppFontSize.md),
        home: Scaffold(body: Center(child: card)),
      ),
    );
  }

  testWidgets('full tag encodes the bare ID in the QR and CODE128 barcode', (
    tester,
  ) async {
    await pumpTag(tester, const LinenTagCard(id: tag));

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byType(BarcodeWidget), findsOneWidget);
    expect(find.text(tag), findsOneWidget);
    expect(
      utf8.decode(
          tester.widget<BarcodeWidget>(find.byType(BarcodeWidget)).data),
      tag,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact tag keeps a long ID inside its constrained width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const longId = 'BSG-A0001XL-VERY-LONG-STRUCTURED-IDENTIFIER';
    await pumpTag(
      tester,
      const LinenTagCard(id: longId, compact: true),
    );

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byType(BarcodeWidget), findsOneWidget);
    expect(find.text(longId), findsOneWidget);
    expect(tester.getSize(find.byType(LinenTagCard)).width,
        lessThanOrEqualTo(118));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact tag can omit the ID when the row already prints it', (
    tester,
  ) async {
    await pumpTag(
      tester,
      const LinenTagCard(id: tag, compact: true, showId: false),
    );

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byType(BarcodeWidget), findsOneWidget);
    expect(find.text(tag), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty ID shows a hint instead of an invalid code', (
    tester,
  ) async {
    await pumpTag(tester, const LinenTagCard(id: '  '));

    expect(find.text('No tag ID'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.byType(BarcodeWidget), findsNothing);
  });
}
