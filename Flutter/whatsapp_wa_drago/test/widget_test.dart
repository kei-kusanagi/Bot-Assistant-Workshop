import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_wa_drago/main.dart';

void main() {
  testWidgets('App carga', (WidgetTester tester) async {
    await tester.pumpWidget(const WaDragoApp());
    expect(find.text('WhatsApp en Dart (Drago)'), findsOneWidget);
  });
}
