const {
  STANDARD_LIMIT_MINUTES,
  spokenMinutes,
  estimateMinutes,
  parseReply,
  trimToMinutes,
  announceDuration,
  finishStory,
} = require('../lib/narration');

const words = (n) => Array.from({ length: n }, (_, i) => `word${i}`).join(' ');
/** `count` sentences of `each` words, in paragraphs of three sentences. */
function story(count, each = 20) {
  const sentences = Array.from({ length: count }, (_, i) => `S${i} ${words(each - 1)}.`);
  const paragraphs = [];
  for (let i = 0; i < sentences.length; i += 3) paragraphs.push(sentences.slice(i, i + 3).join(' '));
  return paragraphs.join('\n\n');
}

describe('spokenMinutes', () => {
  it('counts about 140 spoken words a minute', () => {
    expect(spokenMinutes(words(140), 'English')).toBeCloseTo(1, 5);
    expect(spokenMinutes(words(700), 'Hebrew')).toBeCloseTo(5, 5);
  });

  it('counts characters for languages written without spaces', () => {
    const text = '字'.repeat(600);
    expect(spokenMinutes(text, 'Chinese')).toBeCloseTo(2, 5);
    expect(spokenMinutes(text, 'Japanese')).toBeCloseTo(2, 5);
  });
});

describe('estimateMinutes', () => {
  it('rounds to whole minutes and never says zero', () => {
    expect(estimateMinutes(words(10), 'English')).toBe(1);
    expect(estimateMinutes(words(490), 'English')).toBe(4);
    expect(estimateMinutes(words(1400), 'English')).toBe(10);
  });
});

describe('parseReply', () => {
  it('reads the length label and removes it from what is spoken', () => {
    expect(parseReply('LENGTH: standard\n\nWelcome to the tower.')).toEqual({
      extended: false,
      story: 'Welcome to the tower.',
    });
    expect(parseReply('length: Extended\nWelcome.')).toEqual({ extended: true, story: 'Welcome.' });
  });

  it('treats a reply without a label as a standard one', () => {
    expect(parseReply('Welcome to the tower.')).toEqual({
      extended: false,
      story: 'Welcome to the tower.',
    });
  });
});

describe('trimToMinutes', () => {
  it('leaves a story that fits untouched', () => {
    const text = story(30); // 600 words
    expect(trimToMinutes(text, 10, 'English')).toBe(text);
  });

  it('cuts a long story at a sentence end so that it fits', () => {
    const text = story(100); // 2000 words, over 14 minutes
    const trimmed = trimToMinutes(text, 10, 'English');

    expect(spokenMinutes(trimmed, 'English')).toBeLessThanOrEqual(10);
    expect(spokenMinutes(trimmed, 'English')).toBeGreaterThan(9.5);
    expect(trimmed.endsWith('.')).toBe(true);
    expect(text.startsWith(trimmed)).toBe(true);
    expect(trimmed).toContain('\n\n');
  });
});

describe('announceDuration', () => {
  it('puts the real number where the guide left the token', () => {
    expect(announceDuration('This takes about {{MINUTES}} minutes. Welcome.', 7)).toBe(
      'This takes about 7 minutes. Welcome.',
    );
  });

  it('never fills in less than two, which the sentence is written for', () => {
    expect(announceDuration('About {{MINUTES}} minutes.', 1)).toBe('About 2 minutes.');
  });

  it('leaves a story without the token alone', () => {
    expect(announceDuration('It takes about a minute.', 1)).toBe('It takes about a minute.');
  });
});

describe('finishStory', () => {
  it('caps a standard story at ten minutes and announces its real length', () => {
    const raw = `LENGTH: standard\n\nThis takes about {{MINUTES}} minutes. ${story(110)}`;
    const result = finishStory(raw, 'English');

    expect(STANDARD_LIMIT_MINUTES).toBe(10);
    expect(result.extended).toBe(false);
    expect(result.minutes).toBe(10);
    expect(result.text.startsWith('This takes about 10 minutes.')).toBe(true);
    expect(spokenMinutes(result.text, 'English')).toBeLessThanOrEqual(10);
  });

  it('lets a story the traveller asked to be thorough run longer', () => {
    const raw = `LENGTH: extended\n\nThis takes about {{MINUTES}} minutes. ${story(110)}`;
    const result = finishStory(raw, 'English');

    expect(result.extended).toBe(true);
    expect(result.minutes).toBeGreaterThan(14);
    expect(result.text.startsWith(`This takes about ${result.minutes} minutes.`)).toBe(true);
  });

  it('reports a short story as about a minute', () => {
    const result = finishStory('LENGTH: standard\n\nIt takes about a minute. A small shop.', 'English');
    expect(result).toEqual({
      text: 'It takes about a minute. A small shop.',
      minutes: 1,
      extended: false,
    });
  });
});
