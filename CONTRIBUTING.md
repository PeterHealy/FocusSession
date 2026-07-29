# Contributing

Thanks for helping improve FocusSession.

## Before changing code

Read:

- `README.md` for setup and project boundaries;
- `AGENTS.md` for repository invariants;
- `docs/PRIVACY.md` before touching permissions, storage, observation,
  logging, or native messaging; and
- `docs/ACCEPTANCE_CRITERIA.md` for behavior that must remain true.

## Development workflow

1. Run `./scripts/doctor.sh`.
2. Make one focused change.
3. Add or update tests.
4. Run `./scripts/verify.sh`.
5. Describe any manual Chrome, Brave, or macOS checks in the pull request.

The browser extension has no package dependencies, so no install step is
needed before its tests. The Swift package has no third-party dependencies.

## Pull requests

Keep pull requests small enough to review. Explain:

- what changed and why;
- privacy or permission impact, including “none” when applicable;
- automated checks run; and
- manual checks still outstanding.

Do not include generated builds, local native-host manifests, browser profile
data, state files, screenshots containing personal information, or secrets.

By contributing, you agree that your contribution is licensed under the
repository's MIT License.
