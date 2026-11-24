/**
 * Checks the speech-to-text connection.
 *
 *   npm run stt:check                    sends two seconds of silence
 *   npm run stt:check -- recording.m4a   transcribes a real file (24 MB at most)
 */

const fs = require('fs');
const path = require('path');
const { silentWav } = require('../lib/audio');
const { transcriberFromEnv } = require('../lib/transcriber');

const MEDIA_TYPES = { '.m4a': 'audio/mp4', '.mp3': 'audio/mpeg', '.wav': 'audio/wav', '.ogg': 'audio/ogg' };

/** The audio to send: the file named on the command line, or silence. */
function audioFrom(file) {
  if (!file) return { buffer: silentWav(2), mediaType: 'audio/wav' };
  const mediaType = MEDIA_TYPES[path.extname(file).toLowerCase()] || 'audio/mp4';
  return { buffer: fs.readFileSync(file), mediaType };
}

async function main() {
  const envFile = path.join(__dirname, '..', '.env');
  if (fs.existsSync(envFile)) process.loadEnvFile(envFile);

  const transcriber = transcriberFromEnv(process.env);
  if (!transcriber) throw new Error('Not connected: OPENAI_API_KEY is missing from server/.env');

  const file = process.argv[2];
  const started = Date.now();
  const text = await transcriber.transcribe(audioFrom(file));
  const seconds = ((Date.now() - started) / 1000).toFixed(1);

  console.log(`Speech-to-text is connected (answered in ${seconds}s).`);
  console.log(file ? `Transcript:\n${text}` : 'Sent two seconds of silence; no words expected.');
}

// Report the problem and let Node finish on its own: forcing an exit while
// the network connection is still closing crashes Node on Windows.
main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
