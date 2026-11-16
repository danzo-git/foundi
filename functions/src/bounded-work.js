// Bound independent I/O pipelines without keeping a process-wide data cache.
async function forEachBounded(values, concurrency, action) {
  if (!Number.isInteger(concurrency) || concurrency < 1) throw new RangeError('Invalid concurrency');
  let next = 0, failed = false, failure;
  async function worker() {
    while (!failed && next < values.length) {
      const value = values[next++];
      try { await action(value); } catch (error) {
        if (!failed) failure = error;
        failed = true;
      }
    }
  }
  await Promise.all(Array.from({length: Math.min(values.length, concurrency)}, worker));
  if (failed) throw failure;
}
module.exports = {forEachBounded};
