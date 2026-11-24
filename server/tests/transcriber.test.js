const { createWhisperTranscriber, transcriberFromEnv, MAX_AUDIO_BYTES } = require('../lib/transcriber');

/** A fake fetch that records the request and answers with [status] and [body]. */
function fakeFetch(status, body) {
  const calls = [];
  const fetch = async (url, options) => {
    calls.push({ url, options });
    return { ok: status < 300, status, json: async () => body, text: async () => JSON.stringify(body) };
  };
  fetch.calls = calls;
  return fetch;
}

const audio = { buffer: Buffer.from('audio bytes'), mediaType: 'audio/mp4' };

describe('Whisper transcriber', () => {
  it('sends the audio to the transcription service and returns the text', async () => {
    const fetch = fakeFetch(200, { text: '  Benvenuti a Catania.  ' });
    const transcriber = createWhisperTranscriber({ apiKey: 'sk-test', fetch });

    const text = await transcriber.transcribe(audio);

    expect(text).toBe('Benvenuti a Catania.');
    const { url, options } = fetch.calls[0];
    expect(url).toBe('https://api.openai.com/v1/audio/transcriptions');
    expect(options.method).toBe('POST');
    expect(options.headers.Authorization).toBe('Bearer sk-test');
    const form = options.body;
    expect(form.get('model')).toBe('whisper-1');
    expect(form.get('response_format')).toBe('json');
    expect(form.get('language')).toBeNull();
    const file = form.get('file');
    expect(file.name).toBe('audio.m4a');
    expect(file.type).toBe('audio/mp4');
    expect(Buffer.from(await file.arrayBuffer()).toString()).toBe('audio bytes');
  });

  it('lets the service detect the language unless one is given', async () => {
    const fetch = fakeFetch(200, { text: 'x' });
    const transcriber = createWhisperTranscriber({ apiKey: 'k', fetch, model: 'gpt-4o-transcribe' });

    await transcriber.transcribe({ ...audio, language: 'it' });

    expect(fetch.calls[0].options.body.get('language')).toBe('it');
    expect(fetch.calls[0].options.body.get('model')).toBe('gpt-4o-transcribe');
  });

  it('explains a refusal from the service', async () => {
    const fetch = fakeFetch(401, { error: { message: 'Incorrect API key provided' } });
    const transcriber = createWhisperTranscriber({ apiKey: 'bad', fetch });

    await expect(transcriber.transcribe(audio)).rejects.toThrow(
      'Speech-to-text failed (HTTP 401): Incorrect API key provided',
    );
  });

  it('refuses audio larger than the service accepts, without sending it', async () => {
    const fetch = fakeFetch(200, { text: 'x' });
    const transcriber = createWhisperTranscriber({ apiKey: 'k', fetch });
    const huge = { buffer: Buffer.alloc(MAX_AUDIO_BYTES + 1), mediaType: 'audio/mp4' };

    await expect(transcriber.transcribe(huge)).rejects.toThrow(/too large/);
    expect(fetch.calls).toHaveLength(0);
    expect(MAX_AUDIO_BYTES).toBeLessThanOrEqual(25 * 1024 * 1024);
  });
});

describe('transcriberFromEnv', () => {
  it('is off without a key', () => {
    expect(transcriberFromEnv({})).toBeNull();
  });

  it('uses the key and model from the environment', async () => {
    const fetch = fakeFetch(200, { text: 'x' });
    const transcriber = transcriberFromEnv({ OPENAI_API_KEY: 'sk-env', STT_MODEL: 'my-model' }, fetch);

    await transcriber.transcribe(audio);

    expect(fetch.calls[0].options.headers.Authorization).toBe('Bearer sk-env');
    expect(fetch.calls[0].options.body.get('model')).toBe('my-model');
  });
});
