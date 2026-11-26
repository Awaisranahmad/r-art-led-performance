import 'package:flutter_test/flutter_test.dart';
import 'package:r_art_led_performance/main.dart';

void main() {
  testWidgets('Home screen khulti hai — 3 sections, 30 slots', (tester) async {
    await tester.pumpWidget(const RArtApp());
    await tester.pumpAndSettle();

    expect(find.text('R Art'), findsOneWidget);
    expect(find.text('Section 1  •  Photos 1–10  •  0/10'), findsOneWidget);
    expect(find.text('Section 2  •  Photos 11–20  •  0/10'), findsOneWidget);
    expect(find.text('Section 3  •  Photos 21–30  •  0/10'), findsOneWidget);
    expect(find.text('Export data.h'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
  });
}
