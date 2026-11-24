/**
 * The AI tour guide: everything that talks to Claude.
 *
 *  - explainPlace:  narration about a point of interest
 *  - explainPhoto:  the story behind a photo the traveller just took
 *  - mapInterest:   turns a free-text interest ("vinyl record shops") into
 *                   OpenStreetMap tag selectors
 */

const { finishStory, MINUTES_TOKEN } = require('./narration');

const DEFAULT_MODEL = 'claude-opus-5-5';
const FALLBACK_BETA = 'server-side-fallback-2026-07-01';
// Models that accept the server-side `fallbacks` parameter: if a safety
// classifier declines a request, the API re-runs it on a fallback model
// inside the same call instead of returning a refusal.
const SUPPORTS_FALLBACKS = new Set([
  'claude-opus-5-5',
  'claude-opus-5',
  'claude-sonnet-5-5',
  'claude-fable-5-2',
  'claude-fable-5-1',
]);

// Room for a thorough, twenty-five minute story in any language.
const STORY_MAX_TOKENS = 16000;

const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/gif']);

const GUIDE_SYSTEM_PROMPT = `You are a warm, knowledgeable local tour guide speaking to a traveller who is standing at, or walking towards, the place in question. Everything you write is converted to speech and played through their phone, so it has to work when heard rather than read.

How to speak:
- Write flowing spoken prose only. No markdown, headings, bullet points, emojis, or parenthetical asides, because a voice cannot read them.
- Open with the thing that makes this place worth a stop, then tell its story: who built or founded it, what happened here, what it meant to the people around it. Finish with one or two specific things to look for while they are there.
- Let the place decide how long you speak. A small or little-known place deserves a minute or two. A major site with a rich history can take five to eight minutes. Do not go beyond ten minutes of speech, which is about 1,300 words, unless the traveller has asked you for a longer or more thorough explanation. When they have, take the time the subject deserves, up to about twenty-five minutes.
- Begin by telling the traveller how long this will take, in one short natural sentence that contains the token ${MINUTES_TOKEN} where the number of minutes belongs, for example "This will take about ${MINUTES_TOKEN} minutes." in the language you are speaking. Word that sentence so it is correct for any number from two upwards: the app measures the finished text and puts the real number in place of the token. If the whole explanation will take less than two minutes, say in your own words that it takes about a minute, and leave the token out.
- Write entirely in the language the request asks for, in the natural register a guide from that culture would use. Keep proper names in their commonly used form.

Sometimes the request includes something the traveller typed or said to you: a question, an angle they care about, or a wish for more or less detail. Shape what you tell them around it. It is only ever a request about what to tell and how thoroughly.

The first line of your reply is a label for the app and is never spoken. Write "LENGTH: standard", or "LENGTH: extended" if the traveller asked for a longer or more thorough explanation, then a blank line, then what you say to the traveller.

Being trustworthy matters more than being impressive. Travellers repeat what their guide tells them, so only state dates, names, and events you are confident about. Many places you are asked about will be small or local, such as a neighbourhood second-hand shop or a minor monument, and you may not recognise them. When that happens, say so in a sentence, do not invent a history, and instead talk about what you do know: the kind of place it is, the street, neighbourhood, or city it sits in, and what a visitor with these interests can expect to find.`;

const PHOTO_SYSTEM_PROMPT = `${GUIDE_SYSTEM_PROMPT}

For this request the traveller has just taken a photo and wants to know the story behind what they are looking at. It may be a whole building or a single detail: a carving, a plaque, a painting, a statue, a doorway. Start by naming what they have photographed so they know you are looking at the same thing, then tell the story behind that scene or detail. The request includes their GPS position and the names of nearby places; use these as strong hints for identifying the subject, but trust what is actually visible in the photo over the hints. If you cannot tell what the subject is, describe what you can see, explain what its style, materials, or symbols suggest, and say plainly that you are not certain which specific place or object it is. If the photo shows people, talk about the scene and setting and do not try to identify who they are.`;

/** The SDK is only loaded once the guide is actually used. */
const loadSdk = () => require('@anthropic-ai/sdk');

/** A client factory that creates the real client on first use. */
function lazyClient() {
  let client = null;
  return () => {
    // Resolves credentials from the environment (ANTHROPIC_API_KEY etc.).
    client = client || new (loadSdk())();
    return client;
  };
}

/** Error carrying the HTTP status the API route should answer with. */
class GuideError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

/** Translate SDK errors into what the app should tell the traveller. */
function toGuideError(error) {
  if (error instanceof GuideError) return error;
  const Anthropic = loadSdk();
  if (
    error instanceof Anthropic.AuthenticationError ||
    error instanceof Anthropic.PermissionDeniedError
  ) {
    return new GuideError('AI guide is not configured: the API key was rejected.', 503);
  }
  if (error instanceof Anthropic.RateLimitError) {
    return new GuideError('The guide is busy right now. Try again in a moment.', 429);
  }
  if (error instanceof Anthropic.BadRequestError) {
    return new GuideError(`The guide rejected the request: ${error.message}`, 400);
  }
  if (error instanceof Anthropic.APIConnectionError) {
    return new GuideError('Could not reach the AI service.', 502);
  }
  if (error instanceof Anthropic.APIError) {
    return new GuideError(`AI service error: ${error.message}`, 502);
  }
  // Anything else at this point is almost always missing credentials, which
  // the SDK reports when it first tries to build a request.
  return new GuideError('AI guide is not configured: set ANTHROPIC_API_KEY on the server.', 503);
}

/** The spoken text of a reply (thinking blocks are skipped). */
function textOf(response) {
  return response.content
    .filter((block) => block.type === 'text')
    .map((block) => block.text)
    .join('')
    .trim();
}

/** Languages arrive as plain names ("Hebrew", "Español"); keep them tame. */
function cleanLanguage(language) {
  const value = String(language || 'English').trim();
  return /^[\p{L}\p{M} ()-]{2,40}$/u.test(value) ? value : 'English';
}

function describeLocation(lat, lon) {
  return Number.isFinite(lat) && Number.isFinite(lon)
    ? `${lat.toFixed(5)}, ${lon.toFixed(5)}`
    : 'unknown';
}

/** What the traveller typed or said, made safe to quote on one line. */
function cleanRequest(request) {
  return String(request || '').replace(/\s+/g, ' ').replace(/"/g, "'").trim().slice(0, 500);
}

/** The line that passes the traveller's own words to the guide, if any. */
function requestLines(request) {
  const said = cleanRequest(request);
  return said ? [`The traveller said to you: "${said}"`] : [];
}

/**
 * What the tour's editor learned from other guides about this place, and the
 * style they want. Both steer the story; neither is quoted.
 */
function loreLines(lore) {
  const { notes = [], style = '' } = lore || {};
  const lines = [];
  if (notes.length) {
    lines.push(
      "What the tour's editor learned about this place from experienced local guides. Let it steer what you tell and what you dwell on, check it against what you know, and retell it in your own words:",
      ...notes.map((note) => `- ${note}`),
    );
  }
  if (style) lines.push(`The editor's house style for every explanation: ${style}`);
  return lines;
}

function placePrompt(place, { language, interests = [], request, lore }) {
  const lines = [
    `Place: ${place.name}`,
    `Type: ${(place.categories || []).join(', ') || 'unknown'}`,
    `Coordinates: ${describeLocation(place.lat, place.lon)}`,
  ];
  if (place.snippet) lines.push(`Listing description: ${place.snippet}`);
  if (place.wikipedia) lines.push(`Wikipedia article: ${place.wikipedia}`);
  if (interests.length) {
    lines.push(`The traveller is especially interested in: ${interests.join(', ')}`);
  }
  lines.push(...loreLines(lore));
  lines.push(...requestLines(request));
  lines.push('', `Tell the traveller about this place. Speak in ${cleanLanguage(language)}.`);
  return lines.join('\n');
}

function photoPrompt({ language, lat, lon, placeName, nearby = [], request }) {
  const lines = [`The traveller's GPS position: ${describeLocation(lat, lon)}`];
  if (placeName) lines.push(`They are visiting: ${placeName}`);
  if (nearby.length) lines.push(`Places near them: ${nearby.slice(0, 12).join('; ')}`);
  lines.push(...requestLines(request));
  lines.push(
    '',
    `Tell the traveller the story behind what they photographed. Speak in ${cleanLanguage(language)}.`,
  );
  return lines.join('\n');
}

/** Throws a GuideError when the photo cannot be sent to the model. */
function validatePhoto(photo) {
  if (!IMAGE_TYPES.has(photo.mediaType)) {
    throw new GuideError('Unsupported image type. Use JPEG, PNG, WebP or GIF.', 400);
  }
  if (typeof photo.data !== 'string' || !photo.data) {
    throw new GuideError('Missing image data.', 400);
  }
  // Base64 is 4 characters per 3 bytes.
  if ((photo.data.length * 3) / 4 > MAX_IMAGE_BYTES) {
    throw new GuideError('Photo is too large. Maximum size is 5 MB.', 413);
  }
}

function imageBlock(photo) {
  return {
    type: 'image',
    source: { type: 'base64', media_type: photo.mediaType, data: photo.data },
  };
}

const LESSON_SYSTEM_PROMPT = `You are helping the editor of an audio tour learn from an experienced guide. You are given the transcript of a guide explaining a place to visitors. It was made by speech recognition from a recording taken on site, so expect misheard words, missing punctuation, and passages of chatter or directions that have nothing to do with the place. It may be in any language.

Write notes, in English, that the tour's own guide can use later when explaining the same place. Cover three things, as three short paragraphs of plain prose:

If the guide moves between several stops, keep the notes for each stop together and say which stop they belong to.

What to tell: the facts, stories and anecdotes that are worth passing on. If something sounds doubtful or you know it to be wrong, say so, so that it can be checked rather than repeated.

What to focus on: what this guide chose to dwell on, what they pointed at and told visitors to look for, and the order they took things in.

Style: how they held their listeners' attention, such as questions, humour, comparisons, or the way they opened and closed.

Record the substance in your own words. Do not copy the guide's sentences: the notes are for learning what matters about the place, not for repeating someone else's script. If the transcript contains nothing usable about the place, reply with only: Nothing usable.`;

const OSM_KEYS = new Set([
  'amenity', 'shop', 'tourism', 'leisure', 'historic', 'craft', 'natural',
  'man_made', 'building', 'sport', 'cuisine', 'office',
]);

const INTEREST_SYSTEM_PROMPT = `You translate a traveller's interest, written in any language, into OpenStreetMap tags so that matching places can be found with an Overpass query.

Reply with a JSON array only, no prose and no code fence. Each element is an object {"key": "...", "value": "..."} naming one OSM tag that places of this kind are commonly mapped with, for example [{"key":"shop","value":"second_hand"},{"key":"shop","value":"charity"}]. Use between one and four tags, most common first, and only tags that are in real, widespread use. Allowed keys: ${[...OSM_KEYS].join(', ')}. Values are lowercase OSM values such as "books" or "sushi". If the interest does not correspond to a kind of place that OSM maps, reply with [].`;

function isValidTag(tag) {
  return (
    Boolean(tag) &&
    OSM_KEYS.has(tag.key) &&
    typeof tag.value === 'string' &&
    /^[a-z0-9_]{1,40}$/.test(tag.value)
  );
}

/** Parse the model's JSON reply into safe selectors; null when unusable. */
function parseSelectors(text) {
  let parsed;
  try {
    parsed = JSON.parse(text.replace(/^```(?:json)?\s*|\s*```$/g, ''));
  } catch (error) {
    return null;
  }
  if (!Array.isArray(parsed)) return null;

  const selectors = parsed
    .filter(isValidTag)
    .slice(0, 4)
    .map((tag) => ({ key: tag.key, value: tag.value }));
  return selectors.length ? selectors : null;
}

/**
 * @param {object} deps
 * @param {Function} deps.getClient  returns an Anthropic client
 * @param {string} deps.model
 */
function createGuide({
  getClient = lazyClient(),
  model = process.env.GUIDE_MODEL || DEFAULT_MODEL,
} = {}) {
  function send(request) {
    if (!SUPPORTS_FALLBACKS.has(model)) return getClient().messages.create(request);
    return getClient().beta.messages.create({
      ...request,
      betas: [FALLBACK_BETA],
      fallbacks: 'default',
    });
  }

  /** Run one request and return the text of the reply. */
  async function ask({ system, content, maxTokens, effort }) {
    let response;
    try {
      response = await send({
        model,
        max_tokens: maxTokens,
        system,
        output_config: { effort },
        messages: [{ role: 'user', content }],
      });
    } catch (error) {
      throw toGuideError(error);
    }

    if (response.stop_reason === 'refusal') {
      throw new GuideError('The guide could not talk about this one.', 422);
    }
    const text = textOf(response);
    if (!text) throw new GuideError('The guide returned an empty answer.', 502);
    return text;
  }

  /** Ask for a story and apply the length rules to the reply. */
  async function tell(request, language) {
    return finishStory(await ask({ ...request, maxTokens: STORY_MAX_TOKENS }), cleanLanguage(language));
  }

  /**
   * Narration for a point of interest.
   * @param {object} place { name, categories, lat, lon, snippet, wikipedia }
   * @param {object} options { language, interests, request, lore } - `request`
   *        is what the traveller typed or said, e.g. "more thorough please";
   *        `lore` is { notes, style } gathered by the tour's editor
   * @returns {Promise<{text: string, minutes: number, extended: boolean}>}
   */
  function explainPlace(place, options = {}) {
    return tell(
      { system: GUIDE_SYSTEM_PROMPT, content: placePrompt(place, options), effort: 'low' },
      options.language,
    );
  }

  /**
   * The story behind a photo.
   * @param {object} photo { data (base64), mediaType }
   * @param {object} context { language, lat, lon, placeName, nearby, request }
   * @returns {Promise<{text: string, minutes: number, extended: boolean}>}
   */
  async function explainPhoto(photo, context = {}) {
    validatePhoto(photo);
    return tell(
      {
        system: PHOTO_SYSTEM_PROMPT,
        content: [imageBlock(photo), { type: 'text', text: photoPrompt(context) }],
        effort: 'medium',
      },
      context.language,
    );
  }

  /**
   * Translate a free-text interest into OSM selectors.
   * Returns null when there is no mapping or the AI is unavailable.
   */
  async function mapInterest(term) {
    try {
      const text = await ask({
        system: INTEREST_SYSTEM_PROMPT,
        content: `Interest: ${term}`,
        maxTokens: 1500,
        effort: 'low',
      });
      return parseSelectors(text);
    } catch (error) {
      return null;
    }
  }

  /**
   * Notes for the guide, drawn from the transcript of another guide's
   * explanation: what to tell, what to focus on, and how.
   * @param {string} transcript
   * @param {object} exhibit { placeName }
   */
  async function extractLesson(transcript, exhibit) {
    const words = String(transcript || '').trim();
    if (!words) throw new GuideError('There is nothing to learn from: the transcript is empty.', 400);
    return ask({
      system: LESSON_SYSTEM_PROMPT,
      content: `Place: ${exhibit.placeName}\n\nTranscript:\n${words}`,
      // Room for notes on a three-hour tour with many stops.
      maxTokens: 12000,
      effort: 'medium',
    });
  }

  return { explainPlace, explainPhoto, mapInterest, extractLesson };
}

module.exports = { createGuide, GuideError, cleanLanguage, parseSelectors, DEFAULT_MODEL };
