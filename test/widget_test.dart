import 'package:flutter_test/flutter_test.dart';

import 'package:cloud_spiral/main.dart';

void main() {
  testWidgets('app builds and shows the playground app bar', (tester) async {
    await tester.pumpWidget(const CloudSpiralApp());
    await tester.pump();

    expect(find.text('Fractal cloud spiral — playground'), findsOneWidget);
  });
}
