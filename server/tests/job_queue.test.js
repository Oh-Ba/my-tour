const { createQueue } = require('../lib/job_queue');

const tick = () => new Promise((resolve) => setImmediate(resolve));

describe('job queue', () => {
  it('runs jobs one at a time, in the order they were added', async () => {
    const queue = createQueue();
    const events = [];
    const job = (name) => async () => {
      events.push(`start ${name}`);
      await tick();
      events.push(`end ${name}`);
    };

    queue.add(job('a'));
    queue.add(job('b'));
    await queue.onIdle();

    expect(events).toEqual(['start a', 'end a', 'start b', 'end b']);
  });

  it('carries on after a job fails, and reports the failure', async () => {
    const problems = [];
    const queue = createQueue({ log: (...args) => problems.push(args.join(' ')) });
    const done = [];

    queue.add(async () => {
      throw new Error('boom');
    });
    queue.add(async () => done.push('second'));
    await queue.onIdle();

    expect(done).toEqual(['second']);
    expect(problems[0]).toContain('boom');
  });

  it('is idle straight away when empty, and counts what is waiting', async () => {
    const queue = createQueue();
    await queue.onIdle();
    expect(queue.pending).toBe(0);

    queue.add(tick);
    queue.add(tick);
    expect(queue.pending).toBe(2);
    await queue.onIdle();
    expect(queue.pending).toBe(0);
  });
});
