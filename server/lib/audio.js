/**
 * A silent WAV file: mono, 16-bit. Used to check that the speech-to-text
 * service answers without needing a real recording.
 */
function silentWav(seconds, sampleRate = 16000) {
  const soundBytes = seconds * sampleRate * 2;
  const wav = Buffer.alloc(44 + soundBytes);
  wav.write('RIFF', 0, 'ascii');
  wav.writeUInt32LE(36 + soundBytes, 4);
  wav.write('WAVEfmt ', 8, 'ascii');
  wav.writeUInt32LE(16, 16); // size of the format block
  wav.writeUInt16LE(1, 20); // uncompressed
  wav.writeUInt16LE(1, 22); // one channel
  wav.writeUInt32LE(sampleRate, 24);
  wav.writeUInt32LE(sampleRate * 2, 28); // bytes per second
  wav.writeUInt16LE(2, 32); // bytes per sample
  wav.writeUInt16LE(16, 34); // bits per sample
  wav.write('data', 36, 'ascii');
  wav.writeUInt32LE(soundBytes, 40);
  return wav;
}

module.exports = { silentWav };
