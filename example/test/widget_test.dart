import 'package:flutter_test/flutter_test.dart';
import 'package:vn_editor_example/main.dart';

void main() {
  testWidgets('example exposes the package entry point', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('VN Editor SDK'), findsOneWidget);
    expect(find.text('A native-first editor package'), findsOneWidget);
    expect(find.text('Open editor'), findsOneWidget);
  });
}
