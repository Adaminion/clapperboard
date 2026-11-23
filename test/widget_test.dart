import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clapperboard/main.dart';

const _sampleData = {
  'title': 'SLOW-MO BLAST',
  'scene': '12',
  'take': '3',
  'roll': 'A004',
  'camera': 'FX3',
  'aperture': '2.8',
  'fps': '240',
  'shutter': '500',
  'lens': 'CANON 85',
  'sound': 'MOS',
  'notes': 'ND 0.9',
};

Future<void> _pumpApp(WidgetTester tester, {Size? size}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(const ClapperboardApp());
  await tester.pump();
  await tester.pump();
}

Future<void> _openMenuItem(WidgetTester tester, String text) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App renders core labels', (WidgetTester tester) async {
    await _pumpApp(tester);

    expect(find.text('SCENE'), findsOneWidget);
    expect(find.text('TAKE'), findsOneWidget);
    expect(find.text('ROLL'), findsOneWidget);
    expect(find.text('CAMERA'), findsOneWidget);
    expect(find.text('FPS'), findsOneWidget);
    expect(find.text('SOUND'), findsOneWidget);
    expect(find.text('CLAP'), findsOneWidget);
  });

  test('aperture and shutter get their fixed prefix and suffix', () {
    expect(displayValue('aperture', '2.8'), 'f/2.8');
    expect(displayValue('shutter', '50'), '1/50s');
    // Values typed with the fixed parts are not doubled up.
    expect(displayValue('aperture', 'F/2.8'), 'f/2.8');
    expect(displayValue('shutter', '1/50S'), '1/50s');
    // Empty stays empty; other fields are untouched.
    expect(displayValue('aperture', ''), '');
    expect(displayValue('shutter', ' '), '');
    expect(displayValue('lens', 'CANON 85'), 'CANON 85');
    expect(stripAffixes('shutter', '1/500s'), '500');
  });

  testWidgets('board shows f/ and 1/…s around the stored values',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'clap_data': jsonEncode(_sampleData),
    });
    await _pumpApp(tester);

    expect(find.text('f/2.8'), findsOneWidget);
    expect(find.text('1/500s'), findsOneWidget);
    expect(find.text('240'), findsOneWidget);
  });

  testWidgets('FPS label sits to the right of its cell, other labels left',
      (WidgetTester tester) async {
    await _pumpApp(tester, size: const Size(1180, 820));

    // The grid has three equal columns; FPS is the third.
    final fps = tester.getCenter(find.text('FPS')).dx;
    final sound = tester.getCenter(find.text('SOUND')).dx;
    final columnWidth = 1180 / 3;
    expect(fps, greaterThan(1180 - columnWidth / 2));
    expect(sound, lessThan(1180 - columnWidth / 2));
  });

  for (final entry in {
    'phone portrait': const Size(390, 844),
    'phone landscape': const Size(844, 390),
    'tablet landscape': const Size(1180, 820),
  }.entries) {
    for (final textSize in ['M', 'XL']) {
      testWidgets('lays out without overflow: ${entry.key}, text $textSize',
          (WidgetTester tester) async {
        SharedPreferences.setMockInitialValues({
          'clap_data': jsonEncode(_sampleData),
          'text_size': textSize,
        });
        await _pumpApp(tester, size: entry.value);

        expect(tester.takeException(), isNull);
        // CLAP stays on one line and inside the screen.
        final clap = tester.getRect(find.text('CLAP'));
        expect(clap.left, greaterThanOrEqualTo(0));
        expect(clap.right, lessThanOrEqualTo(entry.value.width));
        expect(clap.bottom, lessThanOrEqualTo(entry.value.height));
        final painted = tester.renderObject<RenderBox>(find.text('CLAP'));
        expect(painted.size.width, greaterThan(painted.size.height));
      });
    }
  }

  testWidgets('SCENE / TAKE / ROLL row can be hidden from the menu',
      (WidgetTester tester) async {
    await _pumpApp(tester, size: const Size(1180, 820));
    expect(find.text('SCENE'), findsOneWidget);

    await _openMenuItem(tester, 'Show SCENE / TAKE / ROLL row');

    expect(find.text('SCENE'), findsNothing);
    expect(find.text('TAKE'), findsNothing);
    expect(find.text('ROLL'), findsNothing);
    expect(find.text('CAMERA'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('show_scene_row'), isFalse);

    await _openMenuItem(tester, 'Show SCENE / TAKE / ROLL row');
    expect(find.text('SCENE'), findsOneWidget);
  });

  testWidgets('dragging a horizontal divider resizes the rows and the font',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'clap_data': jsonEncode(_sampleData),
    });
    await _pumpApp(tester, size: const Size(1180, 820));

    final title = find.text('SLOW-MO BLAST');
    final date = find.textContaining(RegExp(r'^\d{4}-\d\d-\d\d'));
    double fontOf(Finder f) => tester.widget<Text>(f).style!.fontSize!;
    final titleFontBefore = fontOf(title);
    final dateFontBefore = fontOf(date);
    final dateBefore = tester.getCenter(date).dy;
    final cameraBefore = tester.getTopLeft(find.text('CAMERA')).dy;

    // Drag the line under TITLE down.
    final handle = find.byKey(const ValueKey('divider-title'));
    final handleBefore = tester.getCenter(handle).dy;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 20));
    await gesture.moveBy(const Offset(0, 20));
    await gesture.moveBy(const Offset(0, 20));
    await gesture.up();
    await tester.pump();
    final dragged = tester.getCenter(handle).dy - handleBefore;
    expect(dragged, greaterThan(30));

    // The title grew by the drag distance and its font with it. The date row
    // kept its size and just moved down; the space came out of the row below
    // it, so nothing further down moved.
    expect(fontOf(title), greaterThan(titleFontBefore));
    expect(fontOf(date), moreOrLessEquals(dateFontBefore, epsilon: 0.01));
    expect(tester.getCenter(date).dy,
        moreOrLessEquals(dateBefore + dragged, epsilon: 0.01));
    expect(tester.getTopLeft(find.text('CAMERA')).dy,
        moreOrLessEquals(cameraBefore, epsilon: 0.01));

    final prefs = await SharedPreferences.getInstance();
    final saved =
        jsonDecode(prefs.getString('row_sizes')!) as Map<String, dynamic>;
    expect(saved['title'] as num, greaterThan(1));
    expect(saved['date'] as num, moreOrLessEquals(1, epsilon: 0.001));
    expect(saved['scene'] as num, lessThan(2));

    await _openMenuItem(tester, 'Reset row heights');
    expect(fontOf(title), moreOrLessEquals(titleFontBefore, epsilon: 0.01));
    expect(fontOf(date), moreOrLessEquals(dateFontBefore, epsilon: 0.01));
  });

  testWidgets('a tap on a divider still reaches the cell underneath',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'clap_history': jsonEncode({
        'title': ['FIRST FILM', 'SECOND FILM'],
      }),
    });
    await _pumpApp(tester, size: const Size(1180, 820));

    // The grab strip overlaps the bottom edge of the title row; tapping there
    // must still open the title's remembered values.
    final handle = tester.getRect(find.byKey(const ValueKey('divider-title')));
    await tester.tapAt(Offset(handle.center.dx, handle.top + 2));
    await tester.pumpAndSettle();

    expect(find.text('SECOND FILM'), findsOneWidget);
  });

  testWidgets('remembered values can be edited ten per field on their own page',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'clap_history': jsonEncode({
        'lens': ['CANON 85'],
        'aperture': ['f/2.8'],
      }),
    });
    await _pumpApp(tester, size: const Size(1180, 820));
    await _openMenuItem(tester, 'Edit remembered values');

    expect(find.text('Remembered values'), findsOneWidget);
    // Ten rows for a field, the existing value in the first one.
    for (var i = 0; i < 10; i++) {
      expect(find.byKey(ValueKey('list-lens-$i'), skipOffstage: false),
          findsOneWidget);
    }
    expect(
      tester
          .widget<TextField>(
              find.byKey(const ValueKey('list-lens-0'), skipOffstage: false))
          .controller!
          .text,
      'CANON 85',
    );

    Future<void> type(String key, String text) async {
      final field = find.byKey(ValueKey(key), skipOffstage: false);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, text);
    }

    await type('list-lens-1', 'CANON 50');
    await type('list-lens-3', 'CANON 24');
    await type('list-lens-4', 'CANON 50'); // duplicate, dropped on save
    await type('list-aperture-1', '4');

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final saved =
        jsonDecode(prefs.getString('clap_history')!) as Map<String, dynamic>;
    expect(saved['lens'], ['CANON 85', 'CANON 50', 'CANON 24']);
    expect(saved['aperture'], ['2.8', '4']);
    expect(find.text('CLAP'), findsOneWidget);
  });

  testWidgets('a field remembers up to ten values', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'clap_history': jsonEncode({
        'lens': [for (var i = 1; i <= 10; i++) 'LENS $i'],
      }),
    });
    await _pumpApp(tester, size: const Size(1180, 820));

    await tester.tap(find.text('LENS'));
    await tester.pumpAndSettle();

    expect(find.text('LENS 1'), findsOneWidget);
    expect(find.text('LENS 10', skipOffstage: false), findsOneWidget);
  });

  // --- Clap and countdown ---------------------------------------------------

  Color scaffoldColor(WidgetTester tester) => tester
      .widget<Scaffold>(find.byType(Scaffold).first)
      .backgroundColor!;

  String countdownText(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('clap-countdown')))
      .textSpan!
      .toPlainText();

  testWidgets('without the countdown, CLAP flashes at once for one second',
      (WidgetTester tester) async {
    await _pumpApp(tester, size: const Size(1180, 820));
    expect(scaffoldColor(tester), Colors.black);

    await tester.tap(find.text('CLAP'));
    await tester.pump();
    expect(scaffoldColor(tester), Colors.white);
    expect(find.text('CLAP'), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    expect(scaffoldColor(tester), Colors.white);

    await tester.pump(const Duration(milliseconds: 500));
    expect(scaffoldColor(tester), Colors.black);
    expect(find.text('CLAP'), findsOneWidget);
  });

  testWidgets('with the countdown on, the flash comes after the set seconds',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'clap_countdown_on': true,
      'clap_countdown_secs': 3,
    });
    await _pumpApp(tester, size: const Size(1180, 820));

    await tester.tap(find.text('CLAP'));
    await tester.pump();
    // Counting down: no flash yet, 3 seconds on the readout.
    expect(scaffoldColor(tester), Colors.black);
    expect(find.text('CLAP'), findsNothing);
    expect(countdownText(tester), '3  1000');

    await tester.pump(const Duration(milliseconds: 1250));
    expect(scaffoldColor(tester), Colors.black);
    expect(countdownText(tester), '2  0750');

    await tester.pump(const Duration(milliseconds: 1500));
    expect(scaffoldColor(tester), Colors.black);
    expect(countdownText(tester), '1  0250');

    // 3 s after the tap: the clap itself.
    await tester.pump(const Duration(milliseconds: 300));
    expect(scaffoldColor(tester), Colors.white);
    expect(find.byKey(const ValueKey('clap-countdown')), findsNothing);
    expect(find.text('0950'), findsOneWidget);

    // ...which lasts one second, as before.
    await tester.pump(const Duration(milliseconds: 1000));
    expect(scaffoldColor(tester), Colors.black);
    expect(find.text('CLAP'), findsOneWidget);
  });

  testWidgets('tapping again during the countdown cancels it',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'clap_countdown_on': true,
      'clap_countdown_secs': 3,
    });
    await _pumpApp(tester, size: const Size(1180, 820));

    await tester.tap(find.text('CLAP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.tap(find.byKey(const ValueKey('clap-countdown')));
    await tester.pump();
    expect(find.text('CLAP'), findsOneWidget);

    // No flash turns up later.
    await tester.pump(const Duration(milliseconds: 2500));
    expect(scaffoldColor(tester), Colors.black);
    expect(find.text('CLAP'), findsOneWidget);
  });

  testWidgets('checking the countdown option asks for seconds, 10 by default',
      (WidgetTester tester) async {
    await _pumpApp(tester, size: const Size(1180, 820));
    await _openMenuItem(tester, 'Countdown before clap');

    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).controller!.text, '10');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('clap_countdown_on'), isTrue);
    expect(prefs.getInt('clap_countdown_secs'), 10);

    // Unchecking it turns the countdown off without asking anything.
    await _openMenuItem(tester, 'Countdown before clap: 10 s');
    expect(find.byType(TextField), findsNothing);
    expect(prefs.getBool('clap_countdown_on'), isFalse);

    // Checking it again with another number keeps that number.
    await _openMenuItem(tester, 'Countdown before clap');
    await tester.enterText(find.byType(TextField), '5');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(prefs.getInt('clap_countdown_secs'), 5);
    expect(prefs.getBool('clap_countdown_on'), isTrue);
  });

  // --- Colour calibration sheet ---------------------------------------------

  final chart = find.byKey(const ValueKey('color-chart'));

  testWidgets('colour sheet is off by default', (WidgetTester tester) async {
    await _pumpApp(tester, size: const Size(1180, 820));
    expect(chart, findsNothing);
  });

  testWidgets('colour sheet "Fullscreen" sits behind the whole board',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'color_chart': 'full'});
    await _pumpApp(tester, size: const Size(1180, 820));

    expect(tester.getRect(chart), const Rect.fromLTWH(0, 0, 1180, 820));
    // The board is still there and still works on top of it.
    expect(find.text('SCENE'), findsOneWidget);
    await tester.tap(find.text('CLAP'));
    await tester.pump();
    // The flash replaces the sheet with the plain inverted screen.
    expect(chart, findsNothing);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(chart, findsOneWidget);
  });

  testWidgets('colour sheet "Notes" fills just the notes panel',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'color_chart': 'notes'});
    await _pumpApp(tester, size: const Size(1180, 820));

    final rect = tester.getRect(chart);
    final clap = tester.getCenter(find.text('CLAP'));
    final menu = tester.getCenter(find.byIcon(Icons.menu));
    // Between CLAP and the menu button, in the bottom bar only.
    expect(rect.left, greaterThan(clap.dx));
    expect(rect.right, lessThan(menu.dx));
    expect(rect.top, greaterThan(tester.getCenter(find.text('SOUND')).dy));
    expect(rect.contains(Offset(rect.center.dx, clap.dy)), isTrue);
    // No "— notes —" hint drawn over it.
    expect(find.text('— notes —'), findsNothing);
  });

  testWidgets('colour sheet mode is picked from the menu',
      (WidgetTester tester) async {
    await _pumpApp(tester, size: const Size(1180, 820));

    await _openMenuItem(tester, 'Color calibration sheet: Off');
    await tester.tap(find.text('Fullscreen'));
    await tester.pumpAndSettle();
    expect(chart, findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('color_chart'), 'full');

    await _openMenuItem(tester, 'Color calibration sheet: Fullscreen');
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(chart, findsNothing);
    expect(prefs.getString('color_chart'), 'off');
  });
}
