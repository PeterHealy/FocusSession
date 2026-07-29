export const SERVICE_DEFINITIONS = Object.freeze([
  Object.freeze({
    id: "discord",
    label: "Discord",
    domains: Object.freeze(["discord.com", "discord.gg", "discordapp.com"]),
  }),
  Object.freeze({
    id: "whatsapp",
    label: "WhatsApp",
    domains: Object.freeze(["whatsapp.com"]),
  }),
  Object.freeze({
    id: "messenger",
    label: "Messenger",
    domains: Object.freeze(["messenger.com"]),
  }),
  Object.freeze({
    id: "x",
    label: "X / Twitter",
    domains: Object.freeze(["x.com", "twitter.com"]),
  }),
  Object.freeze({
    id: "reddit",
    label: "Reddit",
    domains: Object.freeze(["reddit.com", "redd.it"]),
  }),
  Object.freeze({
    id: "instagram",
    label: "Instagram",
    domains: Object.freeze(["instagram.com"]),
  }),
  Object.freeze({
    id: "facebook",
    label: "Facebook",
    domains: Object.freeze(["facebook.com", "fb.com", "fb.watch"]),
  }),
  Object.freeze({
    id: "twitch",
    label: "Twitch",
    domains: Object.freeze(["twitch.tv"]),
  }),
  Object.freeze({
    id: "linkedin",
    label: "LinkedIn",
    domains: Object.freeze(["linkedin.com", "lnkd.in"]),
  }),
]);

export const DEFAULT_BLOCKED_DOMAINS = Object.freeze(
  ["facebook.com", "instagram.com", "messenger.com", "whatsapp.com"],
);

// This deliberately small list handles common compound suffixes without shipping
// a large public-suffix database. Unknown suffixes safely fall back to the final
// two labels.
export const COMMON_COMPOUND_SUFFIXES = new Set([
  "ac.uk",
  "co.uk",
  "gov.uk",
  "ltd.uk",
  "me.uk",
  "net.uk",
  "org.uk",
  "plc.uk",
  "co.ie",
  "edu.ie",
  "gov.ie",
  "net.ie",
  "org.ie",
  "com.au",
  "edu.au",
  "gov.au",
  "net.au",
  "org.au",
  "asn.au",
  "id.au",
  "co.nz",
  "govt.nz",
  "net.nz",
  "org.nz",
  "ac.nz",
  "com.br",
  "com.cn",
  "com.hk",
  "com.mx",
  "com.my",
  "com.sg",
  "com.tr",
  "com.tw",
  "co.in",
  "co.jp",
  "co.kr",
  "co.za",
]);

function isIpAddress(hostname) {
  return (
    /^\d{1,3}(?:\.\d{1,3}){3}$/.test(hostname) ||
    (hostname.includes(":") && /^[0-9a-f:]+$/i.test(hostname))
  );
}

export function normalizeHostname(value) {
  if (typeof value !== "string") {
    return null;
  }

  let candidate = value.trim().toLowerCase();
  if (!candidate) {
    return null;
  }

  candidate = candidate.replace(/^\*\./, "");
  candidate = candidate.replace(/^\.+|\.+$/g, "");
  if (!candidate || candidate.length > 253 || candidate.includes(" ")) {
    return null;
  }

  try {
    // URL provides punycode normalization and rejects invalid hostnames.
    const url = new URL(`https://${candidate}`);
    const hostname = url.hostname.toLowerCase().replace(/\.$/, "");
    if (
      !hostname ||
      hostname.includes("..") ||
      (!isIpAddress(hostname) &&
        !hostname
          .split(".")
          .every((label) => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i.test(label)))
    ) {
      return null;
    }
    return hostname;
  } catch {
    return null;
  }
}

export function hostnameFromUrl(value) {
  if (typeof value !== "string") {
    return null;
  }

  try {
    const url = new URL(value);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return null;
    }
    return normalizeHostname(url.hostname);
  } catch {
    return null;
  }
}

export function baseDomainFromHostname(value) {
  const hostname = normalizeHostname(value);
  if (!hostname || hostname === "localhost" || isIpAddress(hostname)) {
    return hostname;
  }

  const labels = hostname.split(".");
  if (labels.length <= 2) {
    return hostname;
  }

  const finalTwo = labels.slice(-2).join(".");
  if (COMMON_COMPOUND_SUFFIXES.has(finalTwo) && labels.length >= 3) {
    return labels.slice(-3).join(".");
  }
  return finalTwo;
}

export function baseDomainFromUrl(value) {
  const hostname = hostnameFromUrl(value);
  return hostname ? baseDomainFromHostname(hostname) : null;
}

export function normalizeDomainList(values, fallback = []) {
  const source = Array.isArray(values) ? values : fallback;
  return [
    ...new Set(
      source
        .map((value) => normalizeHostname(value))
        .filter((value) => value !== null),
    ),
  ].sort();
}

export function hostnameMatchesDomain(hostnameValue, domainValue) {
  const hostname = normalizeHostname(hostnameValue);
  const domain = normalizeHostname(domainValue);
  if (!hostname || !domain) {
    return false;
  }
  return hostname === domain || hostname.endsWith(`.${domain}`);
}

export function matchedBlockedDomain(url, blockedDomains = DEFAULT_BLOCKED_DOMAINS) {
  const hostname = hostnameFromUrl(url);
  if (!hostname) {
    return null;
  }

  const matches = normalizeDomainList(blockedDomains).filter((domain) =>
    hostnameMatchesDomain(hostname, domain),
  );
  if (matches.length === 0) {
    return null;
  }

  // Prefer the most specific configured domain when entries overlap.
  return matches.sort((left, right) => right.length - left.length)[0];
}

export function serviceForDomain(domainValue) {
  const hostname = normalizeHostname(domainValue);
  if (!hostname) {
    return null;
  }
  return (
    SERVICE_DEFINITIONS.find((service) =>
      service.domains.some((domain) => hostnameMatchesDomain(hostname, domain)),
    ) ?? null
  );
}
