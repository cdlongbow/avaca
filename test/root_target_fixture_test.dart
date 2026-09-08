import 'package:avaca/main.dart' as legacy_target;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('root target is a lightweight migration fixture', (tester) async {
    legacy_target.main();
    await tester.pump();

    expect(find.textContaining('migration fixture'), findsOneWidget);
    expect(find.textContaining('apps/server'), findsOneWidget);
  });
}
