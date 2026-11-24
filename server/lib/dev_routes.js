/**
 * Developer mode: the routes the app's developer uses to teach the guide.
 *
 * They are only mounted when the server has a DEV_TOKEN, and every request
 * must carry it, so for everyone else this part of the server does not exist.
 */

const crypto = require('crypto');
const express = require('express');

const { createQueue } = require('./job_queue');
const { MAX_AUDIO_BYTES } = require('./transcriber');

// A ten-minute segment of speech is about 2.5 MB; photos are smaller still.
const uploads = express.raw({ type: ['audio/*', 'image/*', 'application/octet-stream'], limit: '30mb' });

const NO_TRANSCRIBER =
  'No speech-to-text service is connected, so this recording is waiting. Set OPENAI_API_KEY in server/.env and restart.';

/** Compare without revealing, through timing, how much of a guess was right. */
function sameToken(given, expected) {
  const a = Buffer.from(String(given || ''));
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

const hasBody = (req) => Buffer.isBuffer(req.body) && req.body.length > 0;
const count = (segments, status) => segments.filter((s) => s.status === status).length;
const allTranscribed = (lesson) =>
  lesson.segments.length > 0 && lesson.segments.every((s) => s.status === 'done');

/** The words of a recording, in the order they were spoken. */
function fullTranscript(lesson) {
  return lesson.segments.map((s) => s.transcript).filter(Boolean).join('\n\n');
}

/**
 * @param {object} deps
 * @param {object} deps.store        see ./store
 * @param {object} deps.guide        { extractLesson }
 * @param {object} [deps.transcriber]  { transcribe({ buffer, mediaType }) -> text };
 *        without one, recordings are kept and wait
 * @param {string} deps.token        the developer's secret
 * @param {object} [deps.queue]      runs transcription in the background
 * @param {Function} [deps.log]
 */
function createDevRouter({
  store,
  guide,
  transcriber = null,
  token,
  queue = createQueue(),
  log = console.error,
}) {
  const router = express.Router();

  router.use((req, res, next) => {
    if (sameToken(req.get('x-dev-token'), token)) return next();
    return res.status(401).json({ error: 'Developer access only' });
  });

  /** What stands in the way of learning from a lesson, if anything. */
  function problemOf(lesson, waiting) {
    const failed = lesson.segments.find((s) => s.status === 'failed');
    if (lesson.problem) return lesson.problem;
    if (failed) return failed.problem;
    return waiting && !transcriber ? NO_TRANSCRIBER : undefined;
  }

  /** A lesson as the app sees it. */
  function lessonView(lesson) {
    const { segments } = lesson;
    const recording = lesson.source === 'recording' && lesson.status === 'kept';
    const awaitingTranscript = recording && segments.some((s) => s.status !== 'done');
    const problem = problemOf(lesson, awaitingTranscript);
    return {
      id: lesson.id,
      source: lesson.source,
      status: lesson.status,
      finished: lesson.finished,
      notes: lesson.notes,
      transcript: lesson.transcript,
      durationMs: segments.reduce((total, s) => total + s.durationMs, 0),
      segmentCount: segments.length,
      transcribedCount: count(segments, 'done'),
      failedCount: count(segments, 'failed'),
      awaitingTranscript,
      // Still being worked on: the app keeps checking back while this is true.
      processing: recording && !lesson.notes && !problem,
      ...(problem ? { problem } : {}),
    };
  }

  const exhibitView = (exhibit) => ({ ...exhibit, lessons: exhibit.lessons.map(lessonView) });
  const viewOf = (exhibitId, lessonId) => lessonView(store.getLesson(exhibitId, lessonId));

  /** Turn a finished lesson's words into notes for the guide. */
  async function learnIfReady(exhibitId, lessonId) {
    const lesson = store.getLesson(exhibitId, lessonId);
    if (!lesson || lesson.status !== 'kept' || !lesson.finished || lesson.notes) return;
    if (lesson.source === 'recording' && !allTranscribed(lesson)) return;

    const transcript = lesson.source === 'recording' ? fullTranscript(lesson) : lesson.transcript;
    try {
      if (!transcript) throw new Error('Nothing could be heard in this recording.');
      const notes = await guide.extractLesson(transcript, store.getExhibit(exhibitId));
      store.updateLesson(exhibitId, lessonId, { transcript, notes, problem: null });
    } catch (error) {
      log('Could not learn from a lesson:', error.message);
      store.updateLesson(exhibitId, lessonId, { problem: error.message });
    }
  }

  /** Transcribe one segment, then learn from the recording if that was the last. */
  async function transcribeSegment(exhibitId, lessonId, index) {
    const lesson = store.getLesson(exhibitId, lessonId);
    const segment = lesson && lesson.segments.find((s) => s.index === index);
    if (!segment || lesson.status !== 'kept' || segment.status === 'done') return;

    try {
      const transcript = await transcriber.transcribe({
        buffer: store.readFile(segment.file),
        mediaType: segment.mediaType,
      });
      store.updateSegment(exhibitId, lessonId, index, { transcript, status: 'done', problem: undefined });
    } catch (error) {
      log('Could not transcribe a segment:', error.message);
      store.updateSegment(exhibitId, lessonId, index, { status: 'failed', problem: error.message });
    }
    await learnIfReady(exhibitId, lessonId);
  }

  /** Queue a segment for transcription; without a transcriber it waits. */
  function enqueueSegment({ exhibitId, lessonId, index }) {
    if (transcriber) queue.add(() => transcribeSegment(exhibitId, lessonId, index));
  }

  const enqueueLearning = ({ exhibitId, lessonId }) =>
    queue.add(() => learnIfReady(exhibitId, lessonId));

  /**
   * Continue what a restart interrupted, or what was waiting for a
   * speech-to-text service to be connected.
   */
  router.resumePending = () => {
    store.pendingSegments().forEach(enqueueSegment);
    store.unlearnedRecordings().forEach(enqueueLearning);
  };

  /** Load the exhibit named in the URL, or answer 404. */
  function withExhibit(handler) {
    return async (req, res) => {
      const exhibit = store.getExhibit(req.params.id);
      if (!exhibit) return res.status(404).json({ error: 'No such exhibit' });
      return handler(req, res, exhibit);
    };
  }

  router.get('/style', (req, res) => res.json({ text: store.getStyle() }));

  router.put('/style', (req, res) => {
    store.setStyle(String((req.body || {}).text || '').slice(0, 4000));
    res.json({ text: store.getStyle() });
  });

  router.get('/exhibits', (req, res) => res.json({ exhibits: store.listExhibits().map(exhibitView) }));

  router.get('/exhibits/:id', withExhibit((req, res, exhibit) => res.json(exhibitView(exhibit))));

  router.post('/exhibits', (req, res) => {
    const { placeId, placeName, lat, lon } = req.body || {};
    if (typeof placeName !== 'string' || !placeName.trim()) {
      return res.status(400).json({ error: 'placeName is required' });
    }
    const exhibit = store.createExhibit({
      placeId: placeId ? String(placeId) : null,
      placeName: placeName.trim().slice(0, 200),
      lat: Number(lat),
      lon: Number(lon),
    });
    return res.status(201).json(exhibit);
  });

  router.delete('/exhibits/:id', (req, res) => {
    return store.removeExhibit(req.params.id)
      ? res.status(204).end()
      : res.status(404).json({ error: 'No such exhibit' });
  });

  /** Start a recording of a guide. Its audio follows in segments. */
  router.post('/exhibits/:id/recordings', withExhibit((req, res, exhibit) => {
    res.status(201).json(lessonView(store.openRecording(exhibit.id)));
  }));

  /**
   * One segment of a recording: body is the audio, ?index= its position and
   * ?durationMs= its length. Answers at once; transcription runs in the
   * background.
   */
  router.post('/exhibits/:id/recordings/:lessonId/segments', uploads, (req, res) => {
    const { id: exhibitId, lessonId } = req.params;
    if (!hasBody(req)) return res.status(400).json({ error: 'The segment is empty' });
    if (req.body.length > MAX_AUDIO_BYTES) {
      return res.status(413).json({ error: 'A segment may be 24 MB at most' });
    }
    const index = Math.max(0, Math.floor(Number(req.query.index) || 0));
    const segment = store.addSegment(exhibitId, lessonId, {
      buffer: req.body,
      mediaType: req.get('content-type').split(';')[0],
      durationMs: Number(req.query.durationMs) || 0,
      index,
    });
    if (!segment) return res.status(404).json({ error: 'No such recording' });

    enqueueSegment({ exhibitId, lessonId, index });
    return res.status(202).json(viewOf(exhibitId, lessonId));
  });

  /** The recording is complete: learn from it once every segment is transcribed. */
  router.post('/exhibits/:id/recordings/:lessonId/finish', (req, res) => {
    const { id: exhibitId, lessonId } = req.params;
    if (!store.finishRecording(exhibitId, lessonId)) {
      return res.status(404).json({ error: 'No such recording' });
    }
    enqueueLearning({ exhibitId, lessonId });
    return res.json(viewOf(exhibitId, lessonId));
  });

  /** Try again what failed or is still waiting in a lesson. */
  router.post('/exhibits/:id/lessons/:lessonId/retry', (req, res) => {
    const { id: exhibitId, lessonId } = req.params;
    const lesson = store.getLesson(exhibitId, lessonId);
    if (!lesson) return res.status(404).json({ error: 'No such lesson' });

    store.updateLesson(exhibitId, lessonId, { problem: null });
    for (const segment of lesson.segments.filter((s) => s.status !== 'done')) {
      store.updateSegment(exhibitId, lessonId, segment.index, { status: 'pending', problem: undefined });
      enqueueSegment({ exhibitId, lessonId, index: segment.index });
    }
    enqueueLearning({ exhibitId, lessonId });
    return res.status(202).json(viewOf(exhibitId, lessonId));
  });

  /** Notes or a transcript typed by the developer; learned from straight away. */
  router.post('/exhibits/:id/lessons', withExhibit(async (req, res, exhibit) => {
    const text = String((req.body || {}).text || '').trim().slice(0, 60000);
    if (!text) return res.status(400).json({ error: 'text is required' });
    const lesson = store.addTypedLesson(exhibit.id, text);
    await learnIfReady(exhibit.id, lesson.id);
    return res.status(201).json(viewOf(exhibit.id, lesson.id));
  }));

  /** "Ignore what I copied": erase a lesson's audio, transcript and notes. */
  router.post('/exhibits/:id/lessons/:lessonId/ignore', (req, res) => {
    const lesson = store.ignoreLesson(req.params.id, req.params.lessonId);
    return lesson ? res.json(lessonView(lesson)) : res.status(404).json({ error: 'No such lesson' });
  });

  /** A photo for travellers to see later: body is the image, ?caption= describes it. */
  router.post('/exhibits/:id/photos', uploads, withExhibit(async (req, res, exhibit) => {
    if (!hasBody(req)) return res.status(400).json({ error: 'The photo is empty' });
    const photo = store.addPhoto(exhibit.id, {
      buffer: req.body,
      mediaType: req.get('content-type').split(';')[0],
      caption: String(req.query.caption || '').slice(0, 300),
    });
    return res.status(201).json(photo);
  }));

  return router;
}

module.exports = { createDevRouter };
