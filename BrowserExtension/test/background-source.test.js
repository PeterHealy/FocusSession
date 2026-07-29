import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);

test("activity append does not reacquire its caller's aggregate queue", async () => {
  const source = await readFile(
    path.join(ROOT, "src/background.js"),
    "utf8",
  );
  const start = source.indexOf(
    "async function appendActivityAggregate",
  );
  const end = source.indexOf(
    "\nfunction rollActivitySegment",
    start,
  );
  assert.ok(start >= 0 && end > start);
  const helperSource = source.slice(start, end);
  assert.doesNotMatch(helperSource, /serialiseAggregateWork\s*\(/);
});

test("fresh extensions keep aggregate domain observation off", async () => {
  const source = await readFile(
    path.join(ROOT, "src/background.js"),
    "utf8",
  );
  assert.match(
    source,
    /const DEFAULT_SETTINGS = Object\.freeze\(\{\s*observeDomainActivity: false,/,
  );
});

test("extension source has no network client or synced storage", async () => {
  const sourceDirectory = path.join(ROOT, "src");
  const pending = [sourceDirectory];
  const files = [];

  while (pending.length > 0) {
    const directory = pending.pop();
    const entries = await readdir(directory, { withFileTypes: true });
    for (const entry of entries) {
      const absolutePath = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        pending.push(absolutePath);
      } else if (entry.name.endsWith(".js")) {
        files.push(absolutePath);
      }
    }
  }

  const source = (
    await Promise.all(files.map((file) => readFile(file, "utf8")))
  ).join("\n");
  assert.doesNotMatch(
    source,
    /\bfetch\s*\(|\bXMLHttpRequest\b|\bWebSocket\b|chrome\.storage\.sync/,
  );
});
