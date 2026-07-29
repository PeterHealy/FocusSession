import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  baseDomainFromUrl,
  COMMON_COMPOUND_SUFFIXES,
  DEFAULT_BLOCKED_DOMAINS,
  hostnameMatchesDomain,
  matchedBlockedDomain,
  normalizeDomainList,
  serviceForDomain,
} from "../src/shared/domains.js";

test("native and browser compound-suffix tables are identical", () => {
  const swiftSource = readFileSync(
    new URL(
      "../../macOS/Sources/FocusSessionCore/DomainSanitizer.swift",
      import.meta.url,
    ),
    "utf8",
  );
  const tableSource = swiftSource.match(
    /commonTwoPartPublicSuffixes:[\s\S]*?=\s*\[([\s\S]*?)\n\s*\]/,
  )?.[1];
  assert.ok(tableSource, "Swift compound-suffix table was not found");

  const swiftSuffixes = [
    ...tableSource.matchAll(/"([^"]+)"/g),
  ].map((match) => match[1]).sort();
  assert.deepEqual(
    swiftSuffixes,
    [...COMMON_COMPOUND_SUFFIXES].sort(),
  );
});

test("fresh installs block only the four default Meta services", () => {
  assert.deepEqual(DEFAULT_BLOCKED_DOMAINS, [
    "facebook.com",
    "instagram.com",
    "messenger.com",
    "whatsapp.com",
  ]);
});

test("subdomains match their configured restricted domain", () => {
  assert.equal(hostnameMatchesDomain("old.reddit.com", "reddit.com"), true);
  assert.equal(hostnameMatchesDomain("notreddit.com", "reddit.com"), false);
  assert.equal(
    matchedBlockedDomain(
      "https://web.whatsapp.com/inbox?private=value",
      DEFAULT_BLOCKED_DOMAINS,
    ),
    "whatsapp.com",
  );
});

test("the most specific configured domain wins", () => {
  assert.equal(
    matchedBlockedDomain("https://chat.example.com/", [
      "example.com",
      "chat.example.com",
    ]),
    "chat.example.com",
  );
});

test("base-domain extraction handles common compound public suffixes", () => {
  assert.equal(
    baseDomainFromUrl("https://news.example.co.uk/private/path"),
    "example.co.uk",
  );
  assert.equal(
    baseDomainFromUrl("https://sub.reddit.com/r/test"),
    "reddit.com",
  );
  assert.equal(
    baseDomainFromUrl("https://news.example.co.ie/story"),
    "example.co.ie",
  );
  assert.equal(baseDomainFromUrl("chrome://settings"), null);
});

test("domain lists are normalized, deduplicated and contain no URLs", () => {
  assert.deepEqual(
    normalizeDomainList(["Reddit.com", "*.reddit.com", "x.com", "bad value"]),
    ["reddit.com", "x.com"],
  );
});

test("known domains resolve to aggregate service identifiers", () => {
  assert.equal(serviceForDomain("old.reddit.com")?.id, "reddit");
  assert.equal(serviceForDomain("messenger.com")?.id, "messenger");
  assert.equal(serviceForDomain("example.com"), null);
});
