import 'package:avaca/components/javbus_verification_dialog.dart';
import 'package:avaca/core/config.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/services/javbus/javbus_verification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('returns selected answers from the verification dialog', (
    tester,
  ) async {
    final challenge = JavBusVerificationChallenge(
      submitUri: Uri.parse('https://www.javbus.com/verify'),
      hiddenFields: {},
      submitFields: {'submit': 'question'},
      questions: [
        JavBusVerificationQuestion(
          name: 'answer',
          prompt: 'Do you agree?',
          options: [
            JavBusVerificationOption(value: 'yes', label: 'Yes'),
            JavBusVerificationOption(value: 'no', label: 'No'),
          ],
        ),
      ],
    );

    Map<String, String>? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: AppTheme.fromPalette(AppPalettes.light),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDialog<Map<String, String>>(
                context: context,
                builder: (_) => JavBusVerificationDialog(challenge: challenge),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit verification'));
    await tester.pumpAndSettle();

    expect(result, {'answer': 'yes'});
  });
}
