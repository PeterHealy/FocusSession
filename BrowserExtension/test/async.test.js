import assert from "node:assert/strict";
import test from "node:test";

import { settleWithin } from "../src/shared/async.js";

test("settleWithin returns fulfilled values", async () => {
  const result = await settleWithin(
    () => Promise.resolve("ready"),
    100,
  );

  assert.deepEqual(result, {
    status: "fulfilled",
    value: "ready",
  });
});

test("settleWithin converts failures into a settled result", async () => {
  const result = await settleWithin(
    () => Promise.reject(new Error("unavailable")),
    100,
  );

  assert.deepEqual(result, { status: "rejected" });
});

test("settleWithin releases work when a browser promise never settles", async () => {
  const startedAt = Date.now();
  const result = await settleWithin(
    () => new Promise(() => {}),
    20,
  );

  assert.deepEqual(result, { status: "timedOut" });
  assert.ok(Date.now() - startedAt < 250);
});
