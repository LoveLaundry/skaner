import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_mobi/features/misc/dashboard_page.dart';
import 'package:love_mobi/ui/kit/data.dart';
import 'package:love_mobi/ui/theme.dart';

void main() {
  testWidgets('dashboard KPI cards fit a narrow phone layout', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.build(AppTheme.light, AppFontSize.md),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: dashboardKpiCardAspectRatio,
              children: [
                for (final label in const [
                  'Revenue',
                  'Collected',
                  'Outstanding',
                  'Collection Rate',
                  'Gate Passes',
                  'Active Clients',
                ])
                  AppStatCard(
                    label: label,
                    value: 'Rs. 12,345',
                    compact: true,
                    icon: Icons.payments_outlined,
                    footer: const Row(
                      children: [
                        Icon(Icons.arrow_upward_rounded, size: 12),
                        SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            '100.0% vs prev',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
