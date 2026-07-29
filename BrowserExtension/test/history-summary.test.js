import assert from "node:assert/strict";
import test from "node:test";

import {
  addVisitToAccumulator,
  createHistoryAccumulator,
  finalizeHistorySummary,
  sanitizeHistorySummary,
} from "../src/shared/history-summary.js";

const CUTOFF = Date.parse("2026-06-29T00:00:00.000Z");

test("history analysis retains only base-domain count and recency", () => {
  const accumulator = createHistoryAccumulator();
  addVisitToAccumulator(
    accumulator,
    "https://old.reddit.com/r/private?query=secret",
    CUTOFF + 1000,
    CUTOFF,
  );
  addVisitToAccumulator(
    accumulator,
    "https://www.reddit.com/user/private",
    CUTOFF + 2000,
    CUTOFF,
  );
  addVisitToAccumulator(
    accumulator,
    "https://example.com/article",
    CUTOFF - 1,
    CUTOFF,
  );

  const result = finalizeHistorySummary(accumulator);
  assert.deepEqual(result, [
    {
      domain: "reddit.com",
      count: 2,
      lastVisitAt: CUTOFF + 2000,
    },
  ]);
  assert.equal(JSON.stringify(result).includes("private"), false);
  assert.equal(JSON.stringify(result).includes("query"), false);
});

test("import sanitizer merges duplicate domains and rejects URL-like fields", () => {
  const result = sanitizeHistorySummary([
    { domain: "Reddit.com", count: 2, lastVisitAt: CUTOFF + 10 },
    {
      domain: "reddit.com",
      count: 3,
      lastVisitAt: CUTOFF + 20,
      url: "https://reddit.com/private",
      title: "Private title",
    },
    { domain: "bad value", count: 10, lastVisitAt: CUTOFF },
  ]);
  assert.deepEqual(result, [
    {
      domain: "reddit.com",
      count: 5,
      lastVisitAt: CUTOFF + 20,
    },
  ]);
  assert.deepEqual(Object.keys(result[0]).sort(), [
    "count",
    "domain",
    "lastVisitAt",
  ]);
});
