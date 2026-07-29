# Agent guide

This repository should be understandable and installable by a person who has
never seen it before. When helping someone, prefer the shortest safe path:

1. Run `./scripts/doctor.sh` and explain any failed requirement in plain
   language.
2. Run `./scripts/verify.sh`.
3. Help the user load `BrowserExtension/` as an unpacked Chrome or Brave
   extension and copy its 32-letter extension ID.
4. Run `./scripts/install-dev.sh EXTENSION_ID` (pass both IDs if Chrome and
   Brave assigned different ones).
5. Ask the user to quit and reopen the browser once, then confirm that the
   extension settings page reports a connection to the macOS app.

Do not ask users to edit generated native-host manifests by hand unless the
installer cannot be used.

## Repository map

- `macOS/Sources/FocusSessionCore/`: session state, persistence, privacy
  minimization, and the native messaging protocol.
- `macOS/Sources/FocusSessionApp/`: menu-bar UI and native-app enforcement.
- `macOS/Sources/FocusSessionNativeHost/`: local Chrome/Brave bridge.
- `BrowserExtension/src/`: Manifest V3 extension and bundled pages.
- `docs/PRODUCT_SPEC.md`: intended behavior.
- `docs/PRIVACY.md`: binding data-handling rules.
- `docs/NATIVE_PROTOCOL.md`: local extension/native contract.
- `docs/ACCEPTANCE_CRITERIA.md`: release gates and manual checks.
- `scripts/`: setup, removal, diagnostics, and verification.

## Non-negotiable privacy rules

- Do not add an account, telemetry, analytics, crash upload, remote
  configuration, network client, or remote asset.
- Never persist, log, or send page titles, complete URLs, paths, queries,
  fragments, messages, page content, screenshots, window contents, or input.
- Configured block entries remain exact normalized hostnames. Aggregate usage
  may contain only a reduced domain, count/duration, and the documented
  observation context.
- Use `chrome.storage.local`, never `chrome.storage.sync`.
- Browser-history access must remain optional and user-initiated.
- Aggregate app/domain observation and suggestions are opt-in on a fresh
  install.
- State and backup files remain owner-only (`0600`) inside an owner-only
  directory (`0700`).

Read `docs/PRIVACY.md` before changing permissions, persistence, observation,
logging, or browser/native messaging.

## Consistency rules

- `FocusSession` is the product and repository name. Use `Focus Session` only
  where natural-language UI copy benefits from the space.
- The common compound-suffix table is duplicated intentionally in
  `DomainSanitizer.swift` and `domains.js`; update both copies and their parity
  test together.
- Keep native request/response names aligned across Swift, JavaScript,
  `docs/NATIVE_PROTOCOL.md`, and protocol tests.
- Keep release versions aligned across `BrowserExtension/manifest.json`,
  `BrowserExtension/package.json`, and the installer-generated app metadata.
- Do not edit or commit `macOS/.build/`, `.swiftpm/`, `node_modules/`, app
  bundles, archives, native-host manifests containing local paths, or secrets.

## Definition of done

- Run `./scripts/verify.sh`.
- Add or update tests for behavior changes.
- Update the product, privacy, protocol, or acceptance documents when their
  contracts change.
- For enforcement or installer changes, also complete the relevant manual
  Chrome and Brave checks in `docs/ACCEPTANCE_CRITERIA.md`.
- State clearly when a result has only automated coverage and still needs a
  hands-on browser or macOS UI check.
