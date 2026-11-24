/**
 * What the developer teaches the app, kept on disk: exhibits (a place with
 * its lessons and photos) and the house style. One JSON file plus a folder
 * of audio and photo files; small enough to read and write whole.
 */

const crypto = require('crypto');
const nodeFs = require('fs');
const path = require('path');
const { calculateDistance } = require('./geo');

const EXTENSIONS = {
  'audio/mp4': 'm4a', 'audio/m4a': 'm4a', 'audio/aac': 'aac', 'audio/mpeg': 'mp3',
  'audio/wav': 'wav', 'audio/webm': 'webm', 'audio/ogg': 'ogg',
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif',
};

/** Two places with the same name this close together are the same place. */
const SAME_PLACE_METERS = 75;

const emptyDb = () => ({ revision: 0, style: '', exhibits: [] });
const sameName = (a, b) => String(a).trim().toLowerCase() === String(b).trim().toLowerCase();

/** Whether an exhibit is about [place] ({ id, name, lat, lon }). */
function isAbout(exhibit, place) {
  if (exhibit.placeId && exhibit.placeId === place.id) return true;
  if (!sameName(exhibit.placeName, place.name)) return false;
  return calculateDistance(exhibit.lat, exhibit.lon, place.lat, place.lon) <= SAME_PLACE_METERS;
}

/**
 * @param {object} deps
 * @param {string} deps.dir      folder to keep everything in
 * @param {object} [deps.fs]     file system (Node's by default)
 * @param {Function} [deps.newId]
 */
function createStore({ dir, fs = nodeFs, newId = () => crypto.randomUUID() }) {
  const dbFile = path.join(dir, 'db.json');
  const filesDir = path.join(dir, 'files');
  fs.mkdirSync(filesDir, { recursive: true });

  function read() {
    return fs.existsSync(dbFile) ? JSON.parse(fs.readFileSync(dbFile, 'utf8')) : emptyDb();
  }

  /** Save, written to a temporary file first so a crash cannot corrupt it. */
  function write(db) {
    const next = { ...db, revision: db.revision + 1 };
    fs.writeFileSync(`${dbFile}.tmp`, JSON.stringify(next, null, 2));
    fs.renameSync(`${dbFile}.tmp`, dbFile);
    return next;
  }

  function saveFile(buffer, mediaType) {
    const name = `${newId()}.${EXTENSIONS[mediaType] || 'bin'}`;
    fs.writeFileSync(path.join(filesDir, name), buffer);
    return name;
  }

  function deleteFile(name) {
    if (name) fs.rmSync(path.join(filesDir, name), { force: true });
  }

  /** Apply `change(exhibit)` to one exhibit and save; null if it is missing. */
  function changeExhibit(id, change) {
    const db = read();
    const exhibit = db.exhibits.find((e) => e.id === id);
    if (!exhibit) return null;
    const result = change(exhibit);
    write(db);
    return result;
  }

  function addLesson(exhibitId, lesson) {
    return changeExhibit(exhibitId, (exhibit) => {
      const added = {
        id: newId(), status: 'kept', transcript: '', notes: '', finished: false, segments: [], ...lesson,
      };
      exhibit.lessons.push(added);
      return added;
    });
  }

  function changeLesson(exhibitId, lessonId, change) {
    return changeExhibit(exhibitId, (exhibit) => {
      const lesson = exhibit.lessons.find((l) => l.id === lessonId);
      if (!lesson) return null;
      change(lesson);
      return lesson;
    });
  }

  return {
    filesDir,

    getStyle: () => read().style,
    setStyle(text) {
      write({ ...read(), style: text });
    },

    listExhibits: () => read().exhibits,
    getExhibit: (id) => read().exhibits.find((e) => e.id === id) || null,

    createExhibit({ placeId = null, placeName, lat, lon }) {
      const db = read();
      const exhibit = {
        id: newId(), placeId, placeName, lat, lon,
        createdAt: new Date().toISOString(), lessons: [], photos: [],
      };
      db.exhibits.push(exhibit);
      write(db);
      return exhibit;
    },

    getLesson(exhibitId, lessonId) {
      const exhibit = this.getExhibit(exhibitId);
      return (exhibit && exhibit.lessons.find((l) => l.id === lessonId)) || null;
    },

    /**
     * Start a recording of a guide. Its audio arrives afterwards in segments
     * (one per stretch between pauses, or every ten minutes), so that hours
     * of speech never travel or get transcribed as a single file.
     */
    openRecording(exhibitId) {
      return addLesson(exhibitId, { source: 'recording' });
    },

    /** Add a segment of audio; one sent again replaces the earlier copy. */
    addSegment(exhibitId, lessonId, { buffer, mediaType, durationMs = 0, index }) {
      const lesson = this.getLesson(exhibitId, lessonId);
      if (!lesson || lesson.source !== 'recording' || lesson.status !== 'kept') return null;

      const segment = {
        index, file: saveFile(buffer, mediaType), mediaType, durationMs, status: 'pending', transcript: '',
      };
      changeLesson(exhibitId, lessonId, (saved) => {
        saved.segments.filter((s) => s.index === index).forEach((old) => deleteFile(old.file));
        saved.segments = [...saved.segments.filter((s) => s.index !== index), segment]
          .sort((a, b) => a.index - b.index);
      });
      return segment;
    },

    /** Record the outcome of transcribing a segment: { transcript, status, problem }. */
    updateSegment(exhibitId, lessonId, index, patch) {
      return changeLesson(exhibitId, lessonId, (lesson) => {
        const segment = lesson.segments.find((s) => s.index === index);
        if (segment) Object.assign(segment, patch);
      });
    },

    /** No more segments will come: the recording can be learned from. */
    finishRecording(exhibitId, lessonId) {
      return changeLesson(exhibitId, lessonId, (lesson) => {
        lesson.finished = true;
      });
    },

    /** Segments of kept recordings that have not been transcribed yet. */
    pendingSegments() {
      return read().exhibits.flatMap((exhibit) =>
        exhibit.lessons
          .filter((lesson) => lesson.status === 'kept')
          .flatMap((lesson) =>
            lesson.segments
              .filter((segment) => segment.status === 'pending')
              .map((segment) => ({ exhibitId: exhibit.id, lessonId: lesson.id, index: segment.index })),
          ),
      );
    },

    /** Finished, kept recordings the guide has not learned from yet. */
    unlearnedRecordings() {
      return read().exhibits.flatMap((exhibit) =>
        exhibit.lessons
          .filter((l) => l.source === 'recording' && l.status === 'kept' && l.finished && !l.notes)
          .map((lesson) => ({ exhibitId: exhibit.id, lessonId: lesson.id })),
      );
    },

    readFile: (name) => fs.readFileSync(path.join(filesDir, name)),

    /** Notes or a transcript the developer typed. */
    addTypedLesson(exhibitId, text) {
      return addLesson(exhibitId, { source: 'typed', transcript: text, finished: true });
    },

    /** Record what was learned, or `problem`: why not (null clears it). */
    updateLesson(exhibitId, lessonId, patch) {
      return changeLesson(exhibitId, lessonId, (lesson) => {
        for (const field of ['transcript', 'notes', 'problem']) {
          if (patch[field] !== undefined) lesson[field] = patch[field];
        }
        if (lesson.problem === null) delete lesson.problem;
      });
    },

    /** Forget a lesson: its audio, transcript and notes are erased. */
    ignoreLesson(exhibitId, lessonId) {
      return changeLesson(exhibitId, lessonId, (lesson) => {
        lesson.segments.forEach((segment) => deleteFile(segment.file));
        Object.assign(lesson, { status: 'ignored', transcript: '', notes: '', segments: [] });
        delete lesson.problem;
      });
    },

    addPhoto(exhibitId, { buffer, mediaType, caption = '' }) {
      if (!this.getExhibit(exhibitId)) return null;
      const photo = { id: newId(), file: saveFile(buffer, mediaType), caption };
      return changeExhibit(exhibitId, (exhibit) => {
        exhibit.photos.push(photo);
        return photo;
      });
    },

    /** Only photos are ever served to the public; never audio. */
    isPhotoFile(name) {
      return read().exhibits.some((e) => e.photos.some((photo) => photo.file === name));
    },

    removeExhibit(id) {
      const db = read();
      const exhibit = db.exhibits.find((e) => e.id === id);
      if (!exhibit) return false;
      const segments = exhibit.lessons.flatMap((lesson) => lesson.segments);
      [...segments, ...exhibit.photos].forEach((item) => deleteFile(item.file));
      write({ ...db, exhibits: db.exhibits.filter((e) => e.id !== id) });
      return true;
    },

    /**
     * Everything travellers benefit from at [place]: the notes of kept
     * lessons, the photos, and the house style. `revision` changes whenever
     * anything is learned or forgotten.
     */
    knowledgeFor(place) {
      const db = read();
      const exhibits = db.exhibits.filter((exhibit) => isAbout(exhibit, place));
      return {
        notes: exhibits
          .flatMap((e) => e.lessons)
          .filter((lesson) => lesson.status === 'kept' && lesson.notes)
          .map((lesson) => lesson.notes),
        photos: exhibits.flatMap((e) => e.photos).map(({ file, caption }) => ({ file, caption })),
        style: db.style,
        revision: db.revision,
      };
    },
  };
}

module.exports = { createStore };
