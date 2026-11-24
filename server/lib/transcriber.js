/**
 * Speech-to-text: turns a piece of recorded audio into text.
 *
 * Every transcriber has one method, `transcribe({ buffer, mediaType,
 * language? }) -> text`, so the service behind it can be swapped (a local
 * model, another provider) without touching the rest of the server.
 */

const WHISPER_URL = 'https://api.openai.com/v1/audio/transcriptions';
const DEFAULT_MODEL = 'whisper-1';

/** The service accepts 25 MB per file; stay a little under it. */
const MAX_AUDIO_BYTES = 24 * 1024 * 1024;
/** A ten-minute piece takes well under a minute; allow for a slow day. */
const TIMEOUT_MS = 10 * 60 * 1000;

const EXTENSIONS = {
  'audio/mp4': 'm4a', 'audio/m4a': 'm4a', 'audio/aac': 'aac', 'audio/mpeg': 'mp3',
  'audio/wav': 'wav', 'audio/webm': 'webm', 'audio/ogg': 'ogg',
};

/** The upload form the service expects. */
function transcriptionForm({ buffer, mediaType, language }, model) {
  const name = `audio.${EXTENSIONS[mediaType] || 'm4a'}`;
  const form = new FormData();
  form.append('file', new File([buffer], name, { type: mediaType }));
  form.append('model', model);
  form.append('response_format', 'json');
  // Without a language the service detects it, which suits guides who speak
  // a different language from the developer.
  if (language) form.append('language', language);
  return form;
}

/** Why the service said no, in its own words when it gave any. */
async function failureMessage(response) {
  let detail = '';
  try {
    detail = (await response.json()).error.message;
  } catch (_) {
    detail = 'no details given';
  }
  return `Speech-to-text failed (HTTP ${response.status}): ${detail}`;
}

/**
 * Transcriber backed by OpenAI's Whisper API.
 * @param {object} deps
 * @param {string} deps.apiKey
 * @param {Function} [deps.fetch]
 * @param {string} [deps.model]
 * @param {string} [deps.url]
 */
function createWhisperTranscriber({
  apiKey,
  fetch = globalThis.fetch,
  model = DEFAULT_MODEL,
  url = WHISPER_URL,
}) {
  async function transcribe(audio) {
    if (audio.buffer.length > MAX_AUDIO_BYTES) {
      throw new Error('This piece of audio is too large for the speech-to-text service (24 MB at most).');
    }
    const response = await fetch(url, {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}` },
      body: transcriptionForm(audio, model),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!response.ok) throw new Error(await failureMessage(response));
    return String((await response.json()).text || '').trim();
  }

  return { transcribe };
}

/** The transcriber the environment asks for; null when none is configured. */
function transcriberFromEnv(env, fetch = globalThis.fetch) {
  if (!env.OPENAI_API_KEY) return null;
  return createWhisperTranscriber({
    apiKey: env.OPENAI_API_KEY,
    model: env.STT_MODEL || DEFAULT_MODEL,
    fetch,
  });
}

module.exports = { createWhisperTranscriber, transcriberFromEnv, MAX_AUDIO_BYTES };
