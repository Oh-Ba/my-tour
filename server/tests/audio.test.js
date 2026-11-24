const { silentWav } = require('../lib/audio');

describe('silentWav', () => {
  it('builds a valid mono 16-bit WAV file of the requested length', () => {
    const wav = silentWav(2, 16000);

    expect(wav.toString('ascii', 0, 4)).toBe('RIFF');
    expect(wav.toString('ascii', 8, 12)).toBe('WAVE');
    expect(wav.readUInt16LE(22)).toBe(1); // channels
    expect(wav.readUInt32LE(24)).toBe(16000); // samples per second
    expect(wav.readUInt32LE(40)).toBe(2 * 16000 * 2); // bytes of sound
    expect(wav.length).toBe(44 + 2 * 16000 * 2);
    expect(wav.readUInt32LE(4)).toBe(wav.length - 8);
  });
});
