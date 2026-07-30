# FocusSession UI and Brand Roadmap

Status: researched backlog
Scope: macOS app, menu-bar surface, browser extension, native enforcement
surfaces, and product identity
Production baseline: the menu-bar label is text only. It reads `Focus` while
inactive and shows the overall session countdown while any session phase is
active.

## Outcome

Create a calm, distinctive, unmistakably native experience that communicates
three ideas without adding noise:

1. FocusSession protects a bounded period of deliberate work.
2. It is private and local by design.
3. It applies firm friction without shame, scores, or visual aggression.

“Beautiful” should mean coherent, legible, quiet, and precise before it means
decorative.

## Research conclusions

- Treat the menu bar as a status-and-control surface, not the main branding
  canvas. Apple describes the Mac menu bar as a place for easy access to app
  commands, and competing focus tools commonly keep a simple countdown visible
  there. The current text-only label is therefore the right production
  baseline. See [Designing for macOS][designing-for-macos],
  [MenuBarExtra][menu-bar-extra], [Flow][flow], and [Kofe Flow][kofe-flow].
- Separate the rich app icon from interface glyphs. Apple expects an app icon
  to express identity and personality, while interface icons should communicate
  one action or state with a streamlined shape. See [App icons][app-icons] and
  [Icons][icons].
- Begin with purpose and brand attributes, then draw. Apple’s current design
  principles begin with identifying what matters most to the people using the
  product. See [Design principles][design-principles] and
  [Branding][branding].
- Use native typography, semantic colors, and system components as the
  foundation. Custom styling should be a restrained layer above the platform,
  not a replacement for it. See [Typography][typography],
  [Color][color], and [Apple Design Resources][design-resources].
- Use materials to establish hierarchy, not decoration. Apple recommends
  applying Liquid Glass sparingly and keeping it out of the content layer.
  Standard SwiftUI components should inherit platform behavior rather than
  recreating glass manually. See [Materials][materials].
- Accessibility is part of the visual system. The design must be checked with
  VoiceOver, keyboard navigation, larger text, Increase Contrast, Reduce
  Transparency, and Reduce Motion. See [Accessibility][accessibility].
- FocusSession’s strongest differentiator is not gamification. Opal emphasizes
  scores and rewards, while Freedom emphasizes cross-device blocking.
  FocusSession should instead own calm local-first enforcement, absolute-time
  clarity, and transparent privacy. See [Opal][opal] and [Freedom][freedom].

## Design north star

### Brand character

- Quiet confidence, not austerity.
- Protective, not punitive.
- Precise, not clinical.
- Warmly local, not cloud-service glossy.
- Serious enough for deep work, but never self-important.

### Experience principles

- One obvious action per state.
- Timing is always unambiguous.
- Secondary controls recede until needed.
- Color never carries meaning alone.
- No shame, streak pressure, productivity score, or moralizing copy.
- No remote font, image, animation, or other asset.
- Visual polish must not weaken the privacy contract or add telemetry.

## Parked concept: hourglass

The animated or progressively filled hourglass is intentionally removed from
production. It remains one possible identity exploration, not the chosen logo.

Do not reintroduce it until all of these gates pass:

- [ ] A brand brief and at least three non-hourglass concept families exist.
- [ ] The static mark is recognizable before animation or progress is added.
- [ ] It remains clear at 16, 18, 24, 32, 64, 128, and 1024 pixels.
- [ ] A monochrome template version works on light, dark, colorful, and
      translucent menu bars.
- [ ] The app-icon version works as a layered macOS icon without thin details.
- [ ] Five-second recognition testing distinguishes it from a generic timer,
      loading indicator, or system hourglass.
- [ ] The mark improves comprehension enough to justify competing with the
      countdown for menu-bar space.
- [ ] Reduce Motion produces a complete, equally clear static experience.
- [ ] A manual acceptance screenshot matrix is reviewed before implementation.

If the concept fails any gate, keep the menu bar text-only and use the selected
brand mark in the app icon, settings, browser extension, and marketing surfaces
instead.

## Prioritized task list

### P0 — Audit and creative brief

- [ ] `UI-001` Capture every current state in light and dark appearance:
      idle, start countdown, focusing, break ready, on break, final ten seconds,
      disconnected extension, blocked page, empty dashboard, populated
      dashboard, settings, errors, confirmations, and native blocking HUD.
- [ ] `UI-002` Repeat the capture on macOS 26 at 1x and 2x display scale, with
      Increase Contrast and Reduce Transparency enabled.
- [ ] `UI-003` Inventory every reusable visual primitive: type style, spacing,
      corner radius, material, separator, button treatment, icon, error style,
      empty state, and timer style.
- [ ] `UI-004` Map the three primary journeys: configure and start; earn, claim,
      and extend a break; understand and recover from a block.
- [ ] `UI-005` Record the top five hierarchy or comprehension problems in each
      journey. Separate functional problems from subjective styling opinions.
- [ ] `BRAND-001` Write a one-page creative brief covering audience, promise,
      personality, anti-personality, differentiation, required assets, and
      forbidden motifs.
- [ ] `BRAND-002` Choose three final brand attributes and three explicit
      anti-attributes. Validate them against the product and privacy specs.
- [ ] `BRAND-003` Build a reference board from native Mac utilities, calm
      productivity tools, editorial typography, physical timing objects, and
      privacy products. Label what is being learned from each reference so the
      result is research rather than imitation.

Deliverable: a signed-off audit and creative brief before visual redesign
begins.

### P1 — Identity and logo exploration

- [ ] `BRAND-010` Explore at least four concept families. Candidates include a
      protected interval, a bounded doorway, a focus aperture, contained
      negative space, or an abstract `F`. Include an hourglass only as one
      family among them.
- [ ] `BRAND-011` Produce 20–30 black-and-white thumbnail sketches before using
      color, gradients, glass, shadows, or animation.
- [ ] `BRAND-012` Reduce the strongest six ideas to single-color vector marks.
      Reject concepts that depend on a wordmark or internal detail to work.
- [ ] `BRAND-013` Test the six marks against common clock, timer, shield,
      hourglass, target, and focus-app icons for accidental similarity.
- [ ] `BRAND-014` Run five-second recognition and preference tests with at least
      five representative Mac users. Ask what the mark feels like before
      explaining the product.
- [ ] `BRAND-015` Develop the strongest three concepts as:
      app icon, monochrome glyph, browser-extension icon, wordmark lockup, and
      one-color mark.
- [ ] `BRAND-016` Test each concept at every required reduction size and on
      light, dark, tinted, clear, and high-contrast appearances.
- [ ] `BRAND-017` Select one concept using a scored rubric: distinctiveness,
      meaning, reduction, platform fit, warmth, longevity, and implementation
      complexity.
- [ ] `BRAND-018` Build the macOS app icon as layered artwork and validate it in
      Apple’s current Icon Composer workflow. Avoid text, UI screenshots, thin
      strokes, and sharp details that disappear at small sizes.
- [ ] `BRAND-019` Produce the final local asset package: editable vector master,
      PDF, PNG exports, macOS icon assets, and Chromium 16/32/48/128-pixel
      extension icons.
- [ ] `BRAND-020` Add icon resources to the installer-generated app bundle and
      extension manifest, then verify release-version and packaging consistency.

Deliverable: one approved identity system with source files and an export
matrix, not merely one PNG.

### P2 — Native design system

- [ ] `DS-001` Define semantic design tokens for backgrounds, grouped surfaces,
      primary and secondary labels, separators, accent, success, warning, and
      destructive actions. Use system colors wherever their meaning matches.
- [ ] `DS-002` Define light, dark, and increased-contrast variants for every
      custom color. Do not hard-code system color values.
- [ ] `DS-003` Keep San Francisco/system typography for the native app. Define a
      small type scale for titles, section labels, supporting copy, timers, and
      tabular numbers.
- [ ] `DS-004` Define a compact spacing scale, corner-radius scale, and window
      content margins. Remove one-off values as surfaces are migrated.
- [ ] `DS-005` Define material usage. Allow native navigation and controls to
      adopt the system appearance; use standard materials for content
      separation; avoid decorative glass cards.
- [ ] `DS-006` Define icon rules: SF Symbols for common actions, the custom mark
      for identity only, monochrome template rendering where the system tints
      the asset, and no emoji icons.
- [ ] `DS-007` Define motion tokens for state transitions and feedback. Keep
      motion short and purposeful, with complete Reduce Motion alternatives.
- [ ] `DS-008` Create reusable SwiftUI components for session headers, timer
      values, section containers, metric rows, restriction rows, empty states,
      inline errors, and primary/secondary/destructive action groups.
- [ ] `DS-009` Mirror the approved semantic tokens in the browser extension’s
      local CSS. Preserve native web controls, focus indicators, and dark mode.
- [ ] `DS-010` Document the system with examples and “do/don’t” cases so future
      changes remain coherent.

Deliverable: one implemented component gallery covering every reusable state.

### P3 — Surface redesign

#### Menu bar and popover

- [ ] `SURFACE-001` Keep the menu-bar label text-only while identity work is in
      progress: `Focus` when idle and overall session time when active.
- [ ] `SURFACE-002` Redesign the idle popover around one primary action. Reduce
      the visual weight of profile and timing controls without hiding them.
- [ ] `SURFACE-003` Redesign the active header so phase, current phase timer,
      overall session end, and next action have an unmistakable hierarchy.
- [ ] `SURFACE-004` Make break-ready and final-ten-second states visually
      distinct without relying on color alone.
- [ ] `SURFACE-005` Move destructive early ending into a clearly secondary
      position while keeping recovery straightforward.
- [ ] `SURFACE-006` Review whether Dashboard, Settings, and Quit need equal
      footer prominence or a compact overflow treatment.

#### Settings

- [ ] `SURFACE-010` Test the current three-tab structure against a sidebar or
      settings-toolbar structure using the macOS UI kit.
- [ ] `SURFACE-011` Separate profile identity, timing, restrictions,
      permissions, privacy, and deletion into a clearer information hierarchy.
- [ ] `SURFACE-012` Make unsaved changes, validation errors, and successful
      saves visible without modal interruption.
- [ ] `SURFACE-013` Improve empty and partially configured states for domains,
      apps, suggestions, Shortcuts, and browser connection.
- [ ] `SURFACE-014` Keep privacy explanations close to the control that changes
      data collection, using concise copy with optional detail.

#### Dashboard

- [ ] `SURFACE-020` Establish a clear first question for the dashboard, such as
      “How have my protected sessions gone?”, instead of treating every metric
      as equal.
- [ ] `SURFACE-021` Group summary metrics into meaningful categories:
      commitment, breaks, recovery, and restricted-service activity.
- [ ] `SURFACE-022` Prototype a restrained session trend or timeline only if it
      answers a real question. Do not introduce a focus score or imply that
      wall-clock time equals attention.
- [ ] `SURFACE-023` Improve history scanning, deletion confirmation, empty
      states, and explanation of privacy-minimized aggregates.

#### Browser and enforcement

- [ ] `SURFACE-030` Align the extension popup, settings, and blocked page with
      the native token system while retaining web accessibility conventions.
- [ ] `SURFACE-031` Make browser connection state clear, calm, and actionable.
- [ ] `SURFACE-032` Redesign the blocked page around service identity, timing,
      and one context-appropriate primary action. Preserve neutral language.
- [ ] `SURFACE-033` Bring the native HUD, focus shield, notifications, alerts,
      and browser overlays into the same visual and copy system.
- [ ] `SURFACE-034` Verify that no visual asset, font, or stylesheet is remote.

Deliverable: high-fidelity designs for every state before broad implementation.

### P4 — Prototype and validation

- [ ] `TEST-001` Build a clickable prototype for the three primary journeys.
- [ ] `TEST-002` Run task-based sessions with at least five representative Mac
      users. Measure first-click success, time-to-understand, errors, and
      confidence rather than aesthetic preference alone.
- [ ] `TEST-003` Run a separate identity test at menu-bar, Finder, Settings,
      notification, and browser-toolbar sizes.
- [ ] `TEST-004` Audit the prototype with VoiceOver, keyboard-only navigation,
      Accessibility Inspector, larger text, Increase Contrast, Reduce
      Transparency, Reduce Motion, and color-vision simulations.
- [ ] `TEST-005` Test menu-bar and popover states against light, dark, and
      colorful wallpapers on built-in and external displays.
- [ ] `TEST-006` Review every timer for stable width, tabular digits, unambiguous
      labels, and correct behavior at under one minute and over one hour.
- [ ] `TEST-007` Review every destructive action for clear consequence,
      confirmation, focus order, and recovery behavior.
- [ ] `TEST-008` Conduct a privacy-language review against `docs/PRIVACY.md`.

Exit criterion: no high-severity comprehension or accessibility issue remains,
and the selected identity passes the reduction matrix.

### P5 — Incremental implementation

- [ ] `BUILD-001` Land design tokens and reusable components without changing
      behavior.
- [ ] `BUILD-002` Migrate the menu popover state by state, with manual
      screenshot acceptance for each state.
- [ ] `BUILD-003` Migrate Settings, preserving permissions, persistence, and
      privacy behavior.
- [ ] `BUILD-004` Migrate Dashboard without adding new persisted data.
- [ ] `BUILD-005` Migrate browser surfaces using only bundled local assets.
- [ ] `BUILD-006` Migrate HUD, shield, notifications, and confirmation alerts.
- [ ] `BUILD-007` Add the approved app and extension icon assets and update the
      development installer to package them.
- [ ] `BUILD-008` Add deterministic visual fixtures or snapshot coverage for
      high-risk states, plus targeted logic tests for state-to-presentation
      mapping.
- [ ] `BUILD-009` Update product, privacy, protocol, and acceptance documents
      wherever a contract changes.
- [ ] `BUILD-010` Run the complete verifier after every implementation slice.

### P6 — Release polish

- [ ] `RELEASE-001` Complete the full screenshot matrix on the release build.
- [ ] `RELEASE-002` Complete manual Chrome and Brave checks for popup, settings,
      blocked page, native connection, session changes, and break expiry.
- [ ] `RELEASE-003` Test fresh install, upgrade, login-item launch, restart,
      browser restart, sleep/wake, and absolute session expiry.
- [ ] `RELEASE-004` Measure launch time, popover responsiveness, idle CPU, and
      memory against the existing acceptance gates.
- [ ] `RELEASE-005` Confirm owner-only state permissions and the absence of
      network clients, analytics, remote configuration, and remote assets.
- [ ] `RELEASE-006` Conduct final copy, localization-readiness, and asset
      licensing reviews.
- [ ] `RELEASE-007` Record unresolved visual ideas in this backlog rather than
      shipping unvalidated experiments.

## Recommended first design sprint

Start only these items:

1. `UI-001` through `UI-005`
2. `BRAND-001` through `BRAND-003`
3. `BRAND-010` through `BRAND-014`
4. `DS-001` through `DS-007`
5. `SURFACE-002`, `SURFACE-003`, and `SURFACE-032`

This produces the evidence needed to choose a direction without prematurely
rewriting the app.

## Definition of ready for implementation

- The creative brief is approved.
- One identity concept has passed recognition and reduction testing.
- Light, dark, high-contrast, and reduced-motion designs exist.
- Every changed state has a high-fidelity design and accessibility annotations.
- The design system names the exact native components and semantic tokens to
  use.
- The work is divided into independently verifiable implementation slices.
- No proposed visual change conflicts with the privacy or local-only rules.

[accessibility]: https://developer.apple.com/design/human-interface-guidelines/accessibility/
[app-icons]: https://developer.apple.com/design/human-interface-guidelines/app-icons
[branding]: https://developer.apple.com/design/human-interface-guidelines/branding
[color]: https://developer.apple.com/design/human-interface-guidelines/color
[design-principles]: https://developer.apple.com/design/human-interface-guidelines/design-principles
[design-resources]: https://developer.apple.com/design/resources/
[designing-for-macos]: https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/
[flow]: https://www.flow.app/
[freedom]: https://freedom.to/freedom-for-mac
[icons]: https://developer.apple.com/design/human-interface-guidelines/icons
[kofe-flow]: https://www.kofeflow.com/
[materials]: https://developer.apple.com/design/human-interface-guidelines/materials
[menu-bar-extra]: https://developer.apple.com/documentation/swiftui/menubarextra
[opal]: https://opalapp.com/screentime
[typography]: https://developer.apple.com/design/human-interface-guidelines/typography
