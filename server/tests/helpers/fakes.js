/** Shared test doubles. */

/** A fake Anthropic client that records requests and returns `reply`. */
function fakeClaude(reply) {
  const calls = [];
  const create = async (params) => {
    calls.push(params);
    if (reply instanceof Error) throw reply;
    return typeof reply === 'function' ? reply(params) : reply;
  };
  return { calls, messages: { create }, beta: { messages: { create } } };
}

const textReply = (text) => ({
  stop_reason: 'end_turn',
  content: [{ type: 'thinking', thinking: '' }, { type: 'text', text }],
});

/** A fake fetch answering per URL: a body object, a status number, or an Error. */
function fakeFetch(answers) {
  const calls = [];
  const fetch = async (url, options) => {
    calls.push({ url, options });
    const answer = answers[url];
    if (answer instanceof Error) throw answer;
    if (typeof answer === 'number') return { ok: false, status: answer, json: async () => ({}) };
    return { ok: true, status: 200, json: async () => answer };
  };
  fetch.calls = calls;
  return fetch;
}

const SAMPLE_POIS = [
  { id: 'near_museum', name: 'City Museum', categories: ['museum'], lat: 0, lon: 0.001, snippet: 'm' },
  { id: 'near_park', name: 'Central Park', categories: ['park'], lat: 0, lon: 0.002, snippet: 'p' },
  { id: 'near_thrift', name: 'Vinyl Corner', categories: ['shopping'], lat: 0, lon: 0.003, snippet: 's' },
  { id: 'far_viewpoint', name: 'Hill Lookout', categories: ['viewpoint'], lat: 0, lon: 0.03, snippet: 'v' },
  { id: 'far_museum', name: 'Remote Museum', categories: ['museum'], lat: 0, lon: 0.04, snippet: 'm' },
  { id: 'too_far', name: 'Distant Lookout', categories: ['viewpoint'], lat: 0, lon: 2, snippet: 'v' },
];

module.exports = { fakeClaude, textReply, fakeFetch, SAMPLE_POIS };
