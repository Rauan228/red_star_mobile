import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redstar_vpn/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: RedStarVpnApp(),
      ),
    );

    // Verify that the title is present.
    expect(find.text('Red Star VPN'), findsOneWidget);
  });
}
