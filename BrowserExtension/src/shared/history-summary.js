import {
  baseDomainFromUrl,
  normalizeHostname,
} from "./domains.js";

export const HISTORY_ANALYSIS_DAYS = 30;
export const MAX_HISTORY_DOMAINS = 5_000;

export function createHistoryAccumulator() {
  return new Map();
}

export function addVisitToAccumulator(
  accumulator,
  url,
  visitTime,
  cutoffTime,
) {
  if (!(accumulator instanceof Map)) {
    throw new TypeError("accumulator must be a Map");
  }

  const timestamp = Number(visitTime);
  if (!Number.isFinite(timestamp) || timestamp < cutoffTime) {
    return false;
  }

  const domain = baseDomainFromUrl(url);
  if (!domain) {
    return false;
  }

  const current = accumulator.get(domain) ?? {
    domain,
    count: 0,
    lastVisitAt: 0,
  };
  current.count += 1;
  current.lastVisitAt = Math.max(current.lastVisitAt, Math.round(timestamp));
  accumulator.set(domain, current);
  return true;
}

export function finalizeHistorySummary(
  accumulator,
  limit = MAX_HISTORY_DOMAINS,
) {
  if (!(accumulator instanceof Map)) {
    return [];
  }
  return [...accumulator.values()]
    .filter(
      (entry) =>
        normalizeHostname(entry.domain) !== null &&
        Number.isInteger(entry.count) &&
        entry.count > 0 &&
        Number.isFinite(entry.lastVisitAt),
    )
    .sort(
      (left, right) =>
        right.count - left.count ||
        right.lastVisitAt - left.lastVisitAt ||
        left.domain.localeCompare(right.domain),
    )
    .slice(0, Math.max(0, limit))
    .map((entry) => ({
      domain: entry.domain,
      count: entry.count,
      lastVisitAt: Math.round(entry.lastVisitAt),
    }));
}

export function sanitizeHistorySummary(entries) {
  if (!Array.isArray(entries)) {
    return [];
  }

  const merged = new Map();
  for (const entry of entries) {
    if (!entry || typeof entry !== "object") {
      continue;
    }
    const domain = normalizeHostname(entry.domain);
    const count = Math.round(Number(entry.count));
    const lastVisitAt = Math.round(Number(entry.lastVisitAt));
    if (
      !domain ||
      !Number.isFinite(count) ||
      count <= 0 ||
      !Number.isFinite(lastVisitAt) ||
      lastVisitAt <= 0
    ) {
      continue;
    }
    const current = merged.get(domain) ?? {
      domain,
      count: 0,
      lastVisitAt: 0,
    };
    current.count += count;
    current.lastVisitAt = Math.max(current.lastVisitAt, lastVisitAt);
    merged.set(domain, current);
  }
  return finalizeHistorySummary(merged);
}
