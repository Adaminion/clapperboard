import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clapperboard/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App renders core labels', (WidgetTester tester) async {
    await tester.pumpWidget(const ClapperboardApp());
    await tester.pump();

    expect(find.text('SCENE'), findsOneWidget);
    expect(find.text('TAKE'), findsOneWidget);
    expect(find.text('ROLL'), findsOneWidget);
    expect(find.text('CAMERA'), findsOneWidget);
    expect(find.text('FPS'), findsOneWidget);
    expect(find.text('SOUND'), findsOneWidget);
    expect(find.text('CLAP'), findsOneWidget);
  });
}
