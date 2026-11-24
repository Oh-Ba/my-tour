import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/services/speech_engine.dart';
import 'package:my_tour/src/services/voice_input.dart';

void main() {
  group('chunkForSpeech', () {
    test('keeps a short text in one piece', () {
      expect(chunkForSpeech('Hello. Welcome to Catania.'), ['Hello. Welcome to Catania.']);
    });

    test('is empty for nothing to say', () {
      expect(chunkForSpeech('   '), isEmpty);
    });

    test('splits a long text at sentence ends, losing nothing', () {
      final sentences = List.generate(40, (i) => 'Sentence number $i is here.');
      final text = sentences.join(' ');

      final chunks = chunkForSpeech(text, maxLength: 200);

      expect(chunks.length, greaterThan(4));
      expect(chunks.every((c) => c.length <= 200), isTrue);
      expect(chunks.every((c) => c.endsWith('.')), isTrue);
      expect(chunks.join(' '), text);
    });

    test('respects paragraph breaks and other sentence endings', () {
      final chunks = chunkForSpeech('Really? Yes!\n\nA new paragraph begins here.', maxLength: 16);
      expect(chunks, ['Really? Yes!', 'A new paragraph', 'begins here.']);
    });

    test('breaks an endless sentence between words', () {
      final text = List.filled(60, 'word').join(' ');
      final chunks = chunkForSpeech(text, maxLength: 50);

      expect(chunks.every((c) => c.length <= 50), isTrue);
      expect(chunks.join(' '), text);
    });

    test('ten minutes of speech stays under what Android accepts at once', () {
      final text = List.filled(1400, 'narration').join(' ');
      expect(chunkForSpeech(text).every((c) => c.length <= maxSpeechChunkLength), isTrue);
      expect(maxSpeechChunkLength, lessThan(4000));
    });
  });

  test('voice input uses the locale format the recogniser expects', () {
    expect(localeIdFor('he-IL'), 'he_IL');
    expect(localeIdFor('en-US'), 'en_US');
  });
}
