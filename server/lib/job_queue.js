/**
 * Runs background jobs one at a time, in order. A job that fails is reported
 * and the next one still runs.
 */
function createQueue({ log = console.error } = {}) {
  let tail = Promise.resolve();
  let pending = 0;

  /** Add an async function to run after everything already waiting. */
  function add(job) {
    pending += 1;
    tail = tail
      .then(job)
      .catch((error) => log('A background job failed:', error.message))
      .finally(() => {
        pending -= 1;
      });
    return tail;
  }

  /** Resolves once nothing is running or waiting, including jobs added meanwhile. */
  async function onIdle() {
    while (pending > 0) await tail;
  }

  return {
    add,
    onIdle,
    get pending() {
      return pending;
    },
  };
}

module.exports = { createQueue };
