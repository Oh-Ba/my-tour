import 'package:flutter/foundation.dart';

/// Where a lesson came from.
enum LessonSource { recording, typed }

/// Something the developer gave the guide to learn from: a recording of
/// another guide, or typed notes.
@immutable
class Lesson {
  final String id;
  final LessonSource source;

  /// The developer decided this one is not good enough; it is not used.
  final bool ignored;

  /// What the guide took from it: what to tell and what to focus on.
  final String notes;

  final int durationMs;

  /// A recording that has been saved but not yet turned into text.
  final bool awaitingTranscript;

  /// The server is still transcribing or learning from it.
  final bool processing;

  /// How many pieces the recording has, and how many are transcribed.
  final int segmentCount;
  final int transcribedCount;

  /// Why it could not be learned from yet, if something went wrong.
  final String? problem;

  const Lesson({
    required this.id,
    required this.source,
    this.ignored = false,
    this.notes = '',
    this.durationMs = 0,
    this.awaitingTranscript = false,
    this.processing = false,
    this.segmentCount = 0,
    this.transcribedCount = 0,
    this.problem,
  });

  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      id: json['id'] as String,
      source: json['source'] == 'typed' ? LessonSource.typed : LessonSource.recording,
      ignored: json['status'] == 'ignored',
      notes: json['notes'] as String? ?? '',
      durationMs: (json['durationMs'] as num?)?.round() ?? 0,
      awaitingTranscript: json['awaitingTranscript'] as bool? ?? false,
      processing: json['processing'] as bool? ?? false,
      segmentCount: (json['segmentCount'] as num?)?.round() ?? 0,
      transcribedCount: (json['transcribedCount'] as num?)?.round() ?? 0,
      problem: json['problem'] as String?,
    );
  }
}

/// A photo taken for travellers to see later.
@immutable
class ExhibitPhoto {
  final String id;
  final String file;
  final String caption;

  const ExhibitPhoto({required this.id, required this.file, this.caption = ''});

  factory ExhibitPhoto.fromJson(Map<String, dynamic> json) {
    return ExhibitPhoto(
      id: json['id'] as String,
      file: json['file'] as String,
      caption: json['caption'] as String? ?? '',
    );
  }
}

/// A place the developer is teaching the guide about.
@immutable
class Exhibit {
  final String id;
  final String placeName;
  final List<Lesson> lessons;
  final List<ExhibitPhoto> photos;

  const Exhibit({
    required this.id,
    required this.placeName,
    this.lessons = const [],
    this.photos = const [],
  });

  factory Exhibit.fromJson(Map<String, dynamic> json) {
    List<T> items<T>(String key, T Function(Map<String, dynamic>) read) {
      return (json[key] as List<dynamic>? ?? const [])
          .map((item) => read(item as Map<String, dynamic>))
          .toList();
    }

    return Exhibit(
      id: json['id'] as String,
      placeName: json['placeName'] as String,
      lessons: items('lessons', Lesson.fromJson),
      photos: items('photos', ExhibitPhoto.fromJson),
    );
  }

  /// This exhibit with [lesson] added, or replacing the one with its id.
  Exhibit withLesson(Lesson lesson) {
    final known = lessons.any((l) => l.id == lesson.id);
    final updated = known
        ? [for (final l in lessons) l.id == lesson.id ? lesson : l]
        : [...lessons, lesson];
    return Exhibit(id: id, placeName: placeName, lessons: updated, photos: photos);
  }

  Exhibit withPhoto(ExhibitPhoto photo) {
    return Exhibit(id: id, placeName: placeName, lessons: lessons, photos: [...photos, photo]);
  }
}
