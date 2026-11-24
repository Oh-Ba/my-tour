import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/features/guide/photo_picker.dart';

void main() {
  test('derives the media type from the file name', () {
    expect(mediaTypeForPath('/tmp/IMG_1.JPG'), 'image/jpeg');
    expect(mediaTypeForPath('photo.jpeg'), 'image/jpeg');
    expect(mediaTypeForPath('scan.png'), 'image/png');
    expect(mediaTypeForPath('a.webp'), 'image/webp');
    expect(mediaTypeForPath('a.gif'), 'image/gif');
  });

  test('treats anything else as JPEG, which is what the camera produces', () {
    expect(mediaTypeForPath('image_picker_123'), 'image/jpeg');
    expect(mediaTypeForPath('photo.heic'), 'image/jpeg');
  });
}
