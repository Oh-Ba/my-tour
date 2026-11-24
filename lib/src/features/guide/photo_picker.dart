import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// A photo ready to be sent to the guide.
@immutable
class PickedPhoto {
  final Uint8List bytes;
  final String mediaType;

  const PickedPhoto({required this.bytes, required this.mediaType});
}

/// Gets a photo from the camera or the gallery.
abstract class PhotoPicker {
  /// Null when the traveller cancels.
  Future<PickedPhoto?> pick({required bool fromCamera});
}

const Map<String, String> _mediaTypes = {
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
};

/// The media type for a file name. Photos are JPEG unless clearly otherwise:
/// the picker re-encodes camera shots (HEIC included) to JPEG.
String mediaTypeForPath(String path) {
  final extension = path.contains('.') ? path.split('.').last.toLowerCase() : '';
  return _mediaTypes[extension] ?? 'image/jpeg';
}

/// [PhotoPicker] using the phone's camera and photo library.
class DevicePhotoPicker implements PhotoPicker {
  DevicePhotoPicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Large enough for the AI to read details, small enough to upload quickly.
  static const double maxSide = 1568;

  @override
  Future<PickedPhoto?> pick({required bool fromCamera}) async {
    final file = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: maxSide,
      maxHeight: maxSide,
      imageQuality: 80,
    );
    if (file == null) return null;
    return PickedPhoto(
      bytes: await file.readAsBytes(),
      mediaType: mediaTypeForPath(file.name),
    );
  }
}

final photoPickerProvider = Provider<PhotoPicker>((ref) => DevicePhotoPicker());
