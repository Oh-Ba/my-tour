const fs = require('fs');
const os = require('os');
const path = require('path');
const request = require('supertest');
const { createApp } = require('../lib/app');
const { createDevRouter } = require('../lib/dev_routes');
const { createStore } = require('../lib/store');
const { createQueue } = require('../lib/job_queue');

const TOKEN = 'secret-dev-token';

function setup({ transcriber, token = TOKEN, dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mytour-dev-')) } = {}) {
  const store = createStore({ dir });
  const queue = createQueue({ log: () => {} });
  const lessons = [];
  const guide = {
    extractLesson: async (transcript, exhibit) => {
      lessons.push({ transcript, placeName: exhibit.placeName });
      return `Notes on: ${transcript}`;
    },
    explainPlace: async () => ({ text: 'A story.', minutes: 2 }),
    explainPhoto: async () => ({ text: 'A photo story.', minutes: 1 }),
  };
  const explained = [];
  guide.explainPlace = async (place, options) => {
    explained.push(options);
    return { text: 'A story.', minutes: 2 };
  };
  const app = createApp({
    searchPois: async () => ({ pois: [], source: 'osm', extendedRadius: null }),
    guide,
    knowledgeFor: store.knowledgeFor,
    isPhotoFile: store.isPhotoFile,
    mediaDir: store.filesDir,
    devRouter: token ? createDevRouter({ store, guide, transcriber, token, queue, log: () => {} }) : null,
    log: () => {},
  });
  const dev = (method, url) => request(app)[method](url).set('x-dev-token', TOKEN);

  /** Start a recording in a new exhibit; returns the URL prefix of the recording. */
  async function openRecording() {
    const { body: exhibit } = await dev('post', '/dev/exhibits').send(coit);
    const { body: lesson } = await dev('post', `/dev/exhibits/${exhibit.id}/recordings`);
    return { exhibit, lesson, base: `/dev/exhibits/${exhibit.id}/recordings/${lesson.id}` };
  }

  const sendSegment = (base, index, words, durationMs = 60000) =>
    dev('post', `${base}/segments?index=${index}&durationMs=${durationMs}`)
      .set('Content-Type', 'audio/mp4')
      .send(Buffer.from(words));

  return { app, store, dev, lessons, explained, queue, dir, openRecording, sendSegment };
}

/** A transcriber that "hears" the bytes of the audio as its words. */
function echoTranscriber() {
  const heard = [];
  return {
    heard,
    transcribe: async (audio) => {
      heard.push(audio);
      const words = audio.buffer.toString();
      if (words.startsWith('FAIL')) throw new Error('service down');
      return words;
    },
  };
}

const coit = { placeId: 'poi_004', placeName: 'Coit Tower', lat: 37.8024, lon: -122.4058 };

describe('developer mode', () => {
  it('does not exist on a server without a developer token', async () => {
    const { app } = setup({ token: null });
    const response = await request(app).get('/dev/exhibits').set('x-dev-token', TOKEN);
    expect(response.status).toBe(404);
  });

  it('refuses anyone without the right token', async () => {
    const { app } = setup();
    expect((await request(app).get('/dev/exhibits')).status).toBe(401);
    expect((await request(app).get('/dev/exhibits').set('x-dev-token', 'guess')).status).toBe(401);
    expect((await request(app).post('/dev/exhibits').send(coit)).status).toBe(401);
  });

  it('creates and lists exhibits', async () => {
    const { dev } = setup();
    const created = await dev('post', '/dev/exhibits').send(coit);
    expect(created.status).toBe(201);
    expect(created.body).toMatchObject({ placeName: 'Coit Tower', lessons: [], photos: [] });

    const listed = await dev('get', '/dev/exhibits');
    expect(listed.body.exhibits).toHaveLength(1);
  });

  it('requires a name for a new exhibit', async () => {
    const { dev } = setup();
    expect((await dev('post', '/dev/exhibits').send({ lat: 1, lon: 2 })).status).toBe(400);
  });

  describe('recording a guide', () => {
    it('accepts a segment at once and transcribes it in the background', async () => {
      const transcriber = echoTranscriber();
      const s = setup({ transcriber });
      const { lesson, base } = await s.openRecording();
      expect(lesson).toMatchObject({ source: 'recording', finished: false, segmentCount: 0 });

      const response = await s.sendSegment(base, 0, 'The tower was built in 1933.', 42000);

      expect(response.status).toBe(202);
      expect(response.body).toMatchObject({ segmentCount: 1, durationMs: 42000, processing: true });

      await s.queue.onIdle();
      expect(transcriber.heard[0]).toMatchObject({ mediaType: 'audio/mp4' });
      expect(transcriber.heard[0].language).toBeUndefined();
      expect(s.lessons).toEqual([], 'nothing is learned until the recording is finished');
    });

    it('learns from the whole recording, in order, once it is finished', async () => {
      const s = setup({ transcriber: echoTranscriber() });
      const { exhibit, lesson, base } = await s.openRecording();
      await s.sendSegment(base, 1, 'Second stop.');
      await s.sendSegment(base, 0, 'First stop.');

      const finished = await s.dev('post', `${base}/finish`);
      expect(finished.body).toMatchObject({ finished: true, segmentCount: 2 });
      await s.queue.onIdle();

      const { body } = await s.dev('get', `/dev/exhibits/${exhibit.id}`);
      expect(body.lessons[0]).toMatchObject({
        id: lesson.id,
        transcript: 'First stop.\n\nSecond stop.',
        notes: 'Notes on: First stop.\n\nSecond stop.',
        transcribedCount: 2,
        durationMs: 120000,
        processing: false,
        awaitingTranscript: false,
      });
      expect(s.lessons).toHaveLength(1);
    });

    it('waits for the last segments if finish arrives before they are transcribed', async () => {
      const s = setup({ transcriber: echoTranscriber() });
      const { exhibit, base } = await s.openRecording();
      await s.sendSegment(base, 0, 'Only stop.');
      await s.dev('post', `${base}/finish`);
      await s.queue.onIdle();

      const { body } = await s.dev('get', `/dev/exhibits/${exhibit.id}`);
      expect(body.lessons[0].notes).toBe('Notes on: Only stop.');
    });

    it('keeps the rest when one segment fails, and can retry it', async () => {
      const transcriber = echoTranscriber();
      const s = setup({ transcriber });
      const { exhibit, lesson, base } = await s.openRecording();
      await s.sendSegment(base, 0, 'Good part.');
      await s.sendSegment(base, 1, 'FAIL this one');
      await s.dev('post', `${base}/finish`);
      await s.queue.onIdle();

      let { body } = await s.dev('get', `/dev/exhibits/${exhibit.id}`);
      expect(body.lessons[0]).toMatchObject({ transcribedCount: 1, failedCount: 1, notes: '', processing: false });
      expect(body.lessons[0].problem).toContain('service down');

      transcriber.transcribe = async (audio) => audio.buffer.toString().replace('FAIL ', '');
      const retried = await s.dev('post', `/dev/exhibits/${exhibit.id}/lessons/${lesson.id}/retry`);
      expect(retried.status).toBe(202);
      await s.queue.onIdle();

      ({ body } = await s.dev('get', `/dev/exhibits/${exhibit.id}`));
      expect(body.lessons[0]).toMatchObject({ failedCount: 0, notes: 'Notes on: Good part.\n\nthis one' });
      expect(body.lessons[0].problem).toBeUndefined();
    });

    it('keeps recordings and says why when no speech-to-text service is connected', async () => {
      const s = setup();
      const { base } = await s.openRecording();
      await s.sendSegment(base, 0, 'words');

      const finished = await s.dev('post', `${base}/finish`);
      await s.queue.onIdle();

      expect(finished.body).toMatchObject({ awaitingTranscript: true, processing: false, notes: '' });
      expect(finished.body.problem).toContain('speech-to-text');
      expect(s.lessons).toEqual([]);
    });

    it('picks up unfinished work after a restart', async () => {
      const first = setup();
      const { exhibit, base } = await first.openRecording();
      await first.sendSegment(base, 0, 'Heard before the restart.');
      await first.dev('post', `${base}/finish`);

      // The server restarts, now with a speech-to-text service connected.
      const second = setup({ transcriber: echoTranscriber(), dir: first.dir });
      second.app.resumeDevWork();
      await second.queue.onIdle();

      const { body } = await second.dev('get', `/dev/exhibits/${exhibit.id}`);
      expect(body.lessons[0].notes).toBe('Notes on: Heard before the restart.');
    });

    it('rejects an empty segment, a huge one, and a segment for an unknown recording', async () => {
      const s = setup();
      const { exhibit, base } = await s.openRecording();

      const empty = await s.dev('post', `${base}/segments?index=0`).set('Content-Type', 'audio/mp4');
      expect(empty.status).toBe(400);

      const huge = await s.dev('post', `${base}/segments?index=0`)
        .set('Content-Type', 'audio/mp4')
        .send(Buffer.alloc(25 * 1024 * 1024));
      expect(huge.status).toBe(413);

      const unknown = await s.sendSegment(`/dev/exhibits/${exhibit.id}/recordings/nope`, 0, 'x');
      expect(unknown.status).toBe(404);
    });

    it('ignoring a recording stops work on it', async () => {
      const transcriber = echoTranscriber();
      const s = setup({ transcriber });
      const { exhibit, lesson, base } = await s.openRecording();
      await s.sendSegment(base, 0, 'words');
      await s.dev('post', `/dev/exhibits/${exhibit.id}/lessons/${lesson.id}/ignore`);
      await s.dev('post', `${base}/finish`);
      await s.queue.onIdle();

      expect(s.lessons).toEqual([]);
      expect(fs.readdirSync(path.join(s.dir, 'files'))).toEqual([]);
    });
  });

  it('learns from notes or a transcript the developer types', async () => {
    const { dev } = setup();
    const { body: exhibit } = await dev('post', '/dev/exhibits').send(coit);

    const response = await dev('post', `/dev/exhibits/${exhibit.id}/lessons`).send({ text: 'Start with the view.' });

    expect(response.status).toBe(201);
    expect(response.body).toMatchObject({ source: 'typed', notes: 'Notes on: Start with the view.' });
  });

  it('ignores a lesson on request', async () => {
    const { dev, store } = setup();
    const { body: exhibit } = await dev('post', '/dev/exhibits').send(coit);
    const { body: lesson } = await dev('post', `/dev/exhibits/${exhibit.id}/lessons`).send({ text: 'Bad take.' });

    const response = await dev('post', `/dev/exhibits/${exhibit.id}/lessons/${lesson.id}/ignore`);

    expect(response.body).toMatchObject({ status: 'ignored', notes: '', transcript: '' });
    expect(store.knowledgeFor({ id: 'poi_004', name: 'Coit Tower', lat: 0, lon: 0 }).notes).toEqual([]);
  });

  it('stores photos for the exhibit', async () => {
    const { dev } = setup();
    const { body: exhibit } = await dev('post', '/dev/exhibits').send(coit);

    const response = await dev('post', `/dev/exhibits/${exhibit.id}/photos?caption=The%20murals`)
      .set('Content-Type', 'image/jpeg')
      .send(Buffer.from('jpeg bytes'));

    expect(response.status).toBe(201);
    expect(response.body).toMatchObject({ caption: 'The murals' });
  });

  it('saves and returns the house style', async () => {
    const { dev } = setup();
    await dev('put', '/dev/style').send({ text: 'Warm, short sentences.' });
    expect((await dev('get', '/dev/style')).body).toEqual({ text: 'Warm, short sentences.' });
  });

  it('discards a whole exhibit', async () => {
    const { dev } = setup();
    const { body: exhibit } = await dev('post', '/dev/exhibits').send(coit);
    expect((await dev('delete', `/dev/exhibits/${exhibit.id}`)).status).toBe(204);
    expect((await dev('get', '/dev/exhibits')).body.exhibits).toEqual([]);
  });

  it('answers 404 for an exhibit that does not exist', async () => {
    const { dev } = setup();
    expect((await dev('post', '/dev/exhibits/nope/lessons').send({ text: 'x' })).status).toBe(404);
    expect((await dev('post', '/dev/exhibits/nope/lessons/x/ignore')).status).toBe(404);
  });
});

describe('what travellers get from the developer\'s work', () => {
  async function teach(setupResult) {
    const { dev } = setupResult;
    const { body: exhibit } = await dev('post', '/dev/exhibits').send(coit);
    await dev('post', `/dev/exhibits/${exhibit.id}/lessons`).send({ text: 'Dwell on the murals.' });
    await dev('put', '/dev/style').send({ text: 'Warm, short sentences.' });
    const { body: photo } = await dev('post', `/dev/exhibits/${exhibit.id}/photos?caption=Murals`)
      .set('Content-Type', 'image/jpeg')
      .send(Buffer.from('jpeg bytes'));
    return photo;
  }
  const place = { id: 'poi_004', name: 'Coit Tower', lat: 37.8024, lon: -122.4058 };

  it('the guide is given the lessons and the house style', async () => {
    const s = setup();
    await teach(s);

    await request(s.app).post('/guide/explain').send({ place, language: 'English' });

    expect(s.explained[0].lore).toEqual({
      notes: ['Notes on: Dwell on the murals.'],
      style: 'Warm, short sentences.',
    });
  });

  it('a story is rewritten after the developer teaches something new', async () => {
    const s = setup();
    await request(s.app).post('/guide/explain').send({ place, language: 'English' });
    await teach(s);
    const after = await request(s.app).post('/guide/explain').send({ place, language: 'English' });

    expect(after.body.cached).toBeUndefined();
    expect(s.explained).toHaveLength(2);
  });

  it('the photos of a place are public, the recordings are not', async () => {
    const s = setup();
    const photo = await teach(s);

    const listed = await request(s.app).get('/places/photos?id=poi_004&name=Coit%20Tower&lat=37.8024&lon=-122.4058');
    expect(listed.body.photos).toEqual([{ url: `/media/${photo.file}`, caption: 'Murals' }]);

    const served = await request(s.app).get(`/media/${photo.file}`);
    expect(served.status).toBe(200);
    expect(served.body.toString()).toBe('jpeg bytes');

    expect((await request(s.app).get('/media/db.json')).status).toBe(404);
    expect((await request(s.app).get('/media/..%2Fdb.json')).status).toBe(404);
  });
});
