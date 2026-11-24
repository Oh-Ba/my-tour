import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/widgets/app_logo.dart';

void main() {
  testWidgets('shows the app logo at the requested size', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: AppLogo(size: 40))));

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, appLogoAsset);
    expect(tester.getSize(find.byType(AppLogo)), const Size(40, 40));
    expect(image.semanticLabel, 'My Tour');
  });

  test('the logo file is bundled with the app', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final data = await rootBundle.load(appLogoAsset);
    expect(data.lengthInBytes, greaterThan(1000));
  });
}
