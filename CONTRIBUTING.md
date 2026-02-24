# Contributing to LoginShot

Thanks for contributing.

## Development setup

- Install Xcode 16+ on macOS 13+.
- Clone the repository.
- Build and test from the repo root:

```bash
xcodebuild -scheme LoginShot -configuration Debug -destination 'platform=macOS' build
xcodebuild -scheme LoginShot -destination 'platform=macOS' test
```

## Branching

- Do not work directly on `master`.
- Create a focused branch:
  - `feature/<short-description>`
  - `fix/<short-description>`
  - `test/<short-description>`
  - `docs/<short-description>`
  - `task/<short-description>`

## Pull requests

Keep PRs small and reviewable.

Each PR should include:

- Why the change is needed.
- What changed (high-level bullets).
- Test evidence (commands and outcomes).
- Risks or rollout notes when relevant.

## Tests and project layout

- `LoginShotTests`: unit and integration-style tests for app behavior.
- Use targeted tests during iteration, then run full suite before merge.

## Coding and formatting

- Follow existing style in touched files.
- Keep changes scoped; avoid unrelated formatting churn unless explicitly requested.
- Prefer clear, maintainable code over cleverness.

## Platform-specific behavior

This project targets macOS behavior (agent app, session events, LaunchAgent startup, AVFoundation capture).

- Validate macOS-specific changes on macOS when possible.
- Keep privacy and transparency constraints in mind.
