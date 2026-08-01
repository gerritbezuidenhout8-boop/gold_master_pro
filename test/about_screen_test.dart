import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/core/constants/app_constants.dart';
import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/screens/about/about_screen.dart';

Future<void> _pumpAbout(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    home: const AboutScreen(),
  ));
  await tester.pump();
}

void main() {
  testWidgets('credits the author', (tester) async {
    await _pumpAbout(tester);

    final credit =
        find.text('Gold Master Pro was designed and made by Luan Rohm');
    await tester.scrollUntilVisible(credit, 200);
    expect(credit, findsOneWidget);
    expect(AppConstants.author, 'Luan Rohm');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows the name and version', (tester) async {
    await _pumpAbout(tester);

    expect(find.text(AppConstants.appName), findsOneWidget);
    // GmpPill uppercases its text.
    expect(find.text('VERSION ${AppConstants.appVersion}'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('describes what the app does', (tester) async {
    await _pumpAbout(tester);

    for (final heading in [
      'Gold Master Score',
      'Full technical suite',
      'Structured trade plans',
      'An honest track record',
    ]) {
      await tester.scrollUntilVisible(find.text(heading), 120);
      expect(find.text(heading), findsOneWidget);
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps the not-financial-advice positioning', (tester) async {
    await _pumpAbout(tester);

    // Matches the shipped copy: "Nothing in this app is financial advice…".
    final disclaimer = find.textContaining('is financial advice');
    await tester.scrollUntilVisible(disclaimer, 200);
    expect(disclaimer, findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('renders under the app theme without overflowing',
      (tester) async {
    await _pumpAbout(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  test('the displayed version is a plain semver string', () {
    expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(AppConstants.appVersion), isTrue,
        reason: 'keep AppConstants.appVersion in step with pubspec.yaml');
  });
}
