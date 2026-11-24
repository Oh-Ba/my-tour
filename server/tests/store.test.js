const fs = require('fs');
const os = require('os');
const path = require('path');
const { createStore } = require('../lib/store');

function tempStore() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mytour-store-'));
  let n = 0;
  return { dir, store: createStore({ dir, newId: () => `id${++n}` }) };
}

const coit = { placeId: 'poi_004', placeName: 'Coit Tower', lat: 37.8024, lon: -122.4058 };
const audio = { buffer: Buffer.from('fake audio'), mediaType: 'audio/mp4', durationMs: 65000, index: 0 };

/** An exhibit with one recording that has one segment. */
function recorded(store) {
  const exhibit = store.createExhibit(coit);
  const lesson = store.openRecording(exhibit.id);
  store.addSegment(exhibit.id, lesson.id, audio);
  return { exhibit, lesson };
}

describe('store', () => {
  it('starts empty', () => {
    const { store } = tempStore();
    expect(store.listExhibits()).toEqual([]);
    expect(store.getStyle()).toBe('');
  });

  it('keeps exhibits across restarts', () => {
    const { dir, store } = tempStore();
    const exhibit = store.createExhibit(coit);
    expect(exhibit).toMatchObject({ id: 'id1', placeName: 'Coit Tower', lessons: [], photos: [] });

    const reopened = createStore({ dir });
    expect(reopened.getExhibit('id1').placeId).toBe('poi_004');
  });

  it('a recording starts empty and collects segments', () => {
    const { dir, store } = tempStore();
    const exhibit = store.createExhibit(coit);
    const lesson = store.openRecording(exhibit.id);
    expect(lesson).toMatchObject({
      source: 'recording', status: 'kept', finished: false, segments: [], transcript: '', notes: '',
    });

    const segment = store.addSegment(exhibit.id, lesson.id, audio);

    expect(segment).toMatchObject({ index: 0, durationMs: 65000, status: 'pending', transcript: '' });
    expect(segment.file.endsWith('.m4a')).toBe(true);
    expect(fs.readFileSync(path.join(dir, 'files', segment.file), 'utf8')).toBe('fake audio');
    expect(store.readFile(segment.file).toString()).toBe('fake audio');
    expect(store.getLesson(exhibit.id, lesson.id).segments).toHaveLength(1);
  });

  it('keeps segments in order however they arrive', () => {
    const { store } = tempStore();
    const exhibit = store.createExhibit(coit);
    const lesson = store.openRecording(exhibit.id);
    store.addSegment(exhibit.id, lesson.id, { ...audio, index: 1 });
    store.addSegment(exhibit.id, lesson.id, { ...audio, index: 0 });

    expect(store.getLesson(exhibit.id, lesson.id).segments.map((s) => s.index)).toEqual([0, 1]);
  });

  it('a segment sent twice replaces the first copy', () => {
    const { dir, store } = tempStore();
    const { exhibit, lesson } = recorded(store);
    store.addSegment(exhibit.id, lesson.id, { ...audio, buffer: Buffer.from('second try') });

    const segments = store.getLesson(exhibit.id, lesson.id).segments;
    expect(segments).toHaveLength(1);
    expect(store.readFile(segments[0].file).toString()).toBe('second try');
    expect(fs.readdirSync(path.join(dir, 'files'))).toHaveLength(1);
  });

  it('records the transcript of a segment and marks a recording finished', () => {
    const { store } = tempStore();
    const { exhibit, lesson } = recorded(store);

    store.updateSegment(exhibit.id, lesson.id, 0, { transcript: 'Built in 1933.', status: 'done' });
    store.finishRecording(exhibit.id, lesson.id);

    const saved = store.getLesson(exhibit.id, lesson.id);
    expect(saved.finished).toBe(true);
    expect(saved.segments[0]).toMatchObject({ transcript: 'Built in 1933.', status: 'done' });
  });

  it('records what was learned from a lesson, or why it could not be', () => {
    const { store } = tempStore();
    const { exhibit, lesson } = recorded(store);

    store.updateLesson(exhibit.id, lesson.id, { transcript: 'Built in 1933...', notes: 'Focus on the murals.' });
    expect(store.getLesson(exhibit.id, lesson.id)).toMatchObject({
      transcript: 'Built in 1933...', notes: 'Focus on the murals.',
    });

    store.updateLesson(exhibit.id, lesson.id, { problem: 'service down' });
    expect(store.getLesson(exhibit.id, lesson.id).problem).toBe('service down');
  });

  it('ignoring a lesson erases what was copied, every audio segment included', () => {
    const { dir, store } = tempStore();
    const { exhibit, lesson } = recorded(store);
    store.addSegment(exhibit.id, lesson.id, { ...audio, index: 1 });
    store.updateLesson(exhibit.id, lesson.id, { transcript: 't', notes: 'n' });

    const ignored = store.ignoreLesson(exhibit.id, lesson.id);

    expect(ignored).toMatchObject({ status: 'ignored', transcript: '', notes: '', segments: [] });
    expect(fs.readdirSync(path.join(dir, 'files'))).toEqual([]);
  });

  it('lists the segments still waiting to be transcribed', () => {
    const { store } = tempStore();
    const { exhibit, lesson } = recorded(store);
    store.addSegment(exhibit.id, lesson.id, { ...audio, index: 1 });
    store.updateSegment(exhibit.id, lesson.id, 0, { transcript: 'x', status: 'done' });

    expect(store.pendingSegments()).toEqual([{ exhibitId: exhibit.id, lessonId: lesson.id, index: 1 }]);

    store.ignoreLesson(exhibit.id, lesson.id);
    expect(store.pendingSegments()).toEqual([]);
  });

  it('stores typed lessons and photos', () => {
    const { dir, store } = tempStore();
    const exhibit = store.createExhibit(coit);
    const typed = store.addTypedLesson(exhibit.id, 'Start with the view.');
    const photo = store.addPhoto(exhibit.id, {
      buffer: Buffer.from('jpg'), mediaType: 'image/jpeg', caption: 'The murals',
    });

    expect(typed).toMatchObject({ source: 'typed', transcript: 'Start with the view.', segments: [] });
    expect(photo).toMatchObject({ caption: 'The murals' });
    expect(photo.file.endsWith('.jpg')).toBe(true);
    expect(store.isPhotoFile(photo.file)).toBe(true);
    expect(fs.existsSync(path.join(dir, 'files', photo.file))).toBe(true);
  });

  it('never serves audio or unknown files as photos', () => {
    const { store } = tempStore();
    const { exhibit, lesson } = recorded(store);
    const [segment] = store.getLesson(exhibit.id, lesson.id).segments;
    expect(store.isPhotoFile(segment.file)).toBe(false);
    expect(store.isPhotoFile('../db.json')).toBe(false);
  });

  it('discarding an exhibit removes it and its files', () => {
    const { dir, store } = tempStore();
    const { exhibit } = recorded(store);
    store.addPhoto(exhibit.id, { buffer: Buffer.from('jpg'), mediaType: 'image/jpeg' });

    store.removeExhibit(exhibit.id);

    expect(store.listExhibits()).toEqual([]);
    expect(fs.readdirSync(path.join(dir, 'files'))).toEqual([]);
  });

  it('reports a missing exhibit or lesson as null', () => {
    const { store } = tempStore();
    expect(store.getExhibit('nope')).toBeNull();
    expect(store.openRecording('nope')).toBeNull();
    expect(store.addSegment('nope', 'x', audio)).toBeNull();
    expect(store.getLesson('nope', 'x')).toBeNull();
    expect(store.ignoreLesson('nope', 'x')).toBeNull();
  });

  it('remembers the house style', () => {
    const { dir, store } = tempStore();
    store.setStyle('Warm, with one joke.');
    expect(createStore({ dir }).getStyle()).toBe('Warm, with one joke.');
  });

  describe('knowledgeFor', () => {
    function taught() {
      const { store } = tempStore();
      const exhibit = store.createExhibit(coit);
      const kept = store.addTypedLesson(exhibit.id, 'a');
      store.updateLesson(exhibit.id, kept.id, { notes: 'Focus on the murals.' });
      const dropped = store.addTypedLesson(exhibit.id, 'b');
      store.updateLesson(exhibit.id, dropped.id, { notes: 'Wrong stuff.' });
      store.ignoreLesson(exhibit.id, dropped.id);
      store.addPhoto(exhibit.id, { buffer: Buffer.from('x'), mediaType: 'image/png', caption: 'Mural' });
      store.setStyle('Short sentences.');
      return store;
    }

    it('gives the kept notes, photos and style for a place by id', () => {
      const knowledge = taught().knowledgeFor({ id: 'poi_004', name: 'Coit Tower', lat: 0, lon: 0 });
      expect(knowledge.notes).toEqual(['Focus on the murals.']);
      expect(knowledge.photos).toEqual([{ file: expect.stringMatching(/\.png$/), caption: 'Mural' }]);
      expect(knowledge.style).toBe('Short sentences.');
    });

    it('recognises the same place under another id by name and position', () => {
      const store = taught();
      const near = store.knowledgeFor({ id: 'osm_way_1', name: 'coit tower', lat: 37.8025, lon: -122.4058 });
      const far = store.knowledgeFor({ id: 'osm_way_2', name: 'Coit Tower', lat: 37.9, lon: -122.4058 });
      expect(near.notes).toEqual(['Focus on the murals.']);
      expect(far.notes).toEqual([]);
    });

    it('gives only the style for a place nobody taught about', () => {
      const knowledge = taught().knowledgeFor({ id: 'other', name: 'Other', lat: 1, lon: 1 });
      expect(knowledge).toMatchObject({ notes: [], photos: [], style: 'Short sentences.' });
    });

    it('changes its revision whenever something is learned or forgotten', () => {
      const store = taught();
      const place = { id: 'poi_004', name: 'Coit Tower', lat: 0, lon: 0 };
      const before = store.knowledgeFor(place).revision;
      store.setStyle('Longer sentences.');
      expect(store.knowledgeFor(place).revision).not.toBe(before);
    });
  });
});
