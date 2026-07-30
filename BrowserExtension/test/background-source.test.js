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

test("unresponsive tabs cannot pin the enforcement state queue", async () => {
  const source = await readFile(
    path.join(ROOT, "src/background.js"),
    "utf8",
  );
  const broadcastStart = source.indexOf(
    "async function broadcastState",
  );
  const broadcastEnd = source.indexOf(
    "\nasync function updateAction",
    broadcastStart,
  );
  assert.ok(broadcastStart >= 0 && broadcastEnd > broadcastStart);
  const broadcastSource = source.slice(broadcastStart, broadcastEnd);
  assert.match(
    broadcastSource,
    /settleWithin\(\s*\(\) => chrome\.tabs\.sendMessage/,
  );

  const redirectStart = source.indexOf(
    "async function enforceRestrictedUrl",
  );
  const redirectEnd = source.indexOf(
    "\nasync function blockOpenRestrictedTabs",
    redirectStart,
  );
  assert.ok(redirectStart >= 0 && redirectEnd > redirectStart);
  const redirectSource = source.slice(redirectStart, redirectEnd);
  assert.match(
    redirectSource,
    /settleWithin\(\s*\(\) =>\s*chrome\.tabs\.update/,
  );
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
