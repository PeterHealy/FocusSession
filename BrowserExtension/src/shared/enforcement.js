import { normalizeDomainList } from "./domains.js";

export const BLOCK_RULE_START = 10_000;
export const BLOCK_RULE_END = 10_999;
export const BLOCKED_PAGE_PATH = "/src/pages/blocked.html";

export function blockedPageUrl(
  extensionRootUrl,
  domain,
  reason,
) {
  const target = new URL(
    BLOCKED_PAGE_PATH.replace(/^\//, ""),
    extensionRootUrl,
  );
  target.searchParams.set("domain", domain);
  target.searchParams.set("reason", reason);
  return target.toString();
}

export function blockingRules(
  domains,
  extensionRootUrl,
  ruleStart = BLOCK_RULE_START,
  ruleEnd = BLOCK_RULE_END,
) {
  return normalizeDomainList(domains)
    .slice(0, ruleEnd - ruleStart + 1)
    .map((domain, index) => ({
      id: ruleStart + index,
      priority: 1,
      action: {
        type: "redirect",
        redirect: {
          // `extensionPath` accepts a path only. A query string in that field
          // can be treated as part of the filename, cancelling the navigation
          // before the local block page renders. A complete extension URL
          // preserves the per-site context reliably in Chrome and Brave.
          url: blockedPageUrl(
            extensionRootUrl,
            domain,
            "network-rule",
          ),
        },
      },
      condition: {
        urlFilter: `||${domain}^`,
        resourceTypes: ["main_frame"],
      },
    }));
}

export function ownDynamicRuleIds(
  rules,
  ruleStart = BLOCK_RULE_START,
  ruleEnd = BLOCK_RULE_END,
) {
  return rules
    .map((rule) => rule.id)
    .filter((id) => id >= ruleStart && id <= ruleEnd);
}
