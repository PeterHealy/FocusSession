import assert from "node:assert/strict";
import test from "node:test";

import { DEFAULT_BLOCKED_DOMAINS } from "../src/shared/domains.js";
import {
  BLOCKED_PAGE_PATH,
  blockedPageUrl,
  blockingRules,
  ownDynamicRuleIds,
} from "../src/shared/enforcement.js";

const EXTENSION_ROOT = "chrome-extension://focus-session-test/";

test("blocked-page URLs preserve the requested service as a query", () => {
  const target = new URL(
    blockedPageUrl(
      EXTENSION_ROOT,
      "linkedin.com",
      "network-rule",
    ),
  );

  assert.equal(target.protocol, "chrome-extension:");
  assert.equal(target.pathname, BLOCKED_PAGE_PATH);
  assert.equal(target.searchParams.get("domain"), "linkedin.com");
  assert.equal(target.searchParams.get("reason"), "network-rule");
});

test("every Deep Work domain redirects to its own local block screen", () => {
  const rules = blockingRules(
    DEFAULT_BLOCKED_DOMAINS,
    EXTENSION_ROOT,
  );

  assert.equal(rules.length, DEFAULT_BLOCKED_DOMAINS.length);
  for (const rule of rules) {
    assert.equal(rule.action.type, "redirect");
    assert.equal("extensionPath" in rule.action.redirect, false);

    const target = new URL(rule.action.redirect.url);
    const domain = target.searchParams.get("domain");
    assert.ok(DEFAULT_BLOCKED_DOMAINS.includes(domain), domain);
    assert.equal(rule.condition.urlFilter, `||${domain}^`);
    assert.deepEqual(rule.condition.resourceTypes, ["main_frame"]);
  }
});

test("FocusSession removes only its reserved dynamic rule range", () => {
  assert.deepEqual(
    ownDynamicRuleIds([
      { id: 9_999 },
      { id: 10_000 },
      { id: 10_200 },
      { id: 10_999 },
      { id: 11_000 },
    ]),
    [10_000, 10_200, 10_999],
  );
});
