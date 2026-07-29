import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);

test("manifest is valid MV3 and declares required capabilities", async () => {
  const manifest = JSON.parse(
    await readFile(path.join(ROOT, "manifest.json"), "utf8"),
  );
  assert.equal(manifest.manifest_version, 3);
  assert.equal(manifest.background.type, "module");
  for (const permission of [
    "declarativeNetRequestWithHostAccess",
    "history",
    "idle",
    "nativeMessaging",
    "storage",
  ]) {
    const declared = [
      ...(manifest.permissions ?? []),
      ...(manifest.optional_permissions ?? []),
    ];
    assert.ok(declared.includes(permission), permission);
  }
  assert.ok(manifest.optional_permissions.includes("history"));
  assert.ok(!manifest.permissions.includes("history"));
});

test("every manifest-referenced local entry point exists", async () => {
  const manifest = JSON.parse(
    await readFile(path.join(ROOT, "manifest.json"), "utf8"),
  );
  const files = [
    manifest.background.service_worker,
    manifest.action.default_popup,
    manifest.options_page,
    ...manifest.content_scripts.flatMap((entry) => entry.js),
  ];
  await Promise.all(
    files.map(async (relativePath) => {
      const contents = await readFile(path.join(ROOT, relativePath), "utf8");
      assert.ok(contents.length > 0, relativePath);
    }),
  );
});
