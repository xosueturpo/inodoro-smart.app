import 'package:flutter_test/flutter_test.dart';
import 'package:inodoro_inteligente/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Pantalla principal muestra las 2 opciones de busqueda', (tester) async {
    await tester.pumpWidget(const InodoroSmartApp());
    await tester.pumpAndSettle();

    expect(find.text('Inodoros Fuertes'), findsOneWidget);
    expect(find.text('Buscar en Bluetooth'), findsOneWidget);
    expect(find.text('Buscar en LAN'), findsOneWidget);
  });
}
