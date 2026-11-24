/**
 * The rules for how long the guide speaks.
 *
 * The model writes the story; this module measures it, keeps it within the
 * limit unless the traveller asked for more, and fills in the real duration
 * where the guide announces it.
 */

/** A story runs no longer than this unless the traveller asked for more. */
const STANDARD_LIMIT_MINUTES = 10;

/** Pace of the phone's voice at the app's speech rate. */
const WORDS_PER_MINUTE = 140;
/** Chinese and Japanese are written without spaces; count characters. */
const CHARACTERS_PER_MINUTE = 300;

/** Where the guide leaves room for the number of minutes. */
const MINUTES_TOKEN = '{{MINUTES}}';

const countsCharacters = (language) => /chinese|japanese|中文|日本語/i.test(language || '');

/** How long the text takes to say aloud, in minutes. */
function spokenMinutes(text, language) {
  if (countsCharacters(language)) return text.replace(/\s/g, '').length / CHARACTERS_PER_MINUTE;
  return text.split(/\s+/).filter(Boolean).length / WORDS_PER_MINUTE;
}

/** The duration as a traveller would say it: whole minutes, at least one. */
function estimateMinutes(text, language) {
  return Math.max(1, Math.round(spokenMinutes(text, language)));
}

/**
 * Split the model's reply into its length label and what is spoken.
 * The label is the first line: `LENGTH: standard` or `LENGTH: extended`.
 */
function parseReply(raw) {
  const label = raw.match(/^\s*LENGTH:\s*(standard|extended)[^\n]*\n?/i);
  return {
    extended: label ? label[1].toLowerCase() === 'extended' : false,
    story: (label ? raw.slice(label[0].length) : raw).trim(),
  };
}

/** Sentences with the whitespace that follows them, so joining restores the text. */
function sentencePieces(text) {
  return text.split(/(?<=[.!?…])(\s+)|(?<=[。！？])/u).filter(Boolean);
}

/** The longest run of whole sentences from the start that fits in [limit]. */
function trimToMinutes(story, limit, language) {
  if (spokenMinutes(story, language) <= limit) return story;

  let kept = '';
  for (const piece of sentencePieces(story)) {
    if (spokenMinutes(kept + piece, language) > limit) break;
    kept += piece;
  }
  return kept.trimEnd() || story;
}

/**
 * Fill in the number of minutes. The guide's sentence is written for two or
 * more ("about {{MINUTES}} minutes"); shorter stories say "about a minute"
 * in their own words and carry no token.
 */
function announceDuration(story, minutes) {
  return story.replaceAll(MINUTES_TOKEN, String(Math.max(2, minutes)));
}

/**
 * Turn the model's raw reply into the story the traveller hears.
 * @returns {{ text: string, minutes: number, extended: boolean }}
 */
function finishStory(raw, language) {
  const { extended, story } = parseReply(raw);
  const fitted = extended ? story : trimToMinutes(story, STANDARD_LIMIT_MINUTES, language);
  const minutes = estimateMinutes(fitted, language);
  return { text: announceDuration(fitted, minutes), minutes, extended };
}

module.exports = {
  STANDARD_LIMIT_MINUTES,
  MINUTES_TOKEN,
  spokenMinutes,
  estimateMinutes,
  parseReply,
  trimToMinutes,
  announceDuration,
  finishStory,
};
