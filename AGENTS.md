# AGENTS.md — LoginShot

This file guides coding agents (OpenCode, Cursor agents, Copilot agents, etc.) working on this repository.

## Goal (v1)

Build a macOS agent app that:
1) captures a webcam snapshot when the agent starts after user login (`session-open`),
2) captures a snapshot when the user session becomes active/unlocked (`unlock`),
3) writes the image into a configurable folder,
4) writes a sidecar metadata JSON file per capture.

See `README.md` for user-facing behavior and examples.

Keep v1 local-only: no cloud APIs, no face recognition.

## Scope and Product Constraints

- Respect user privacy and OS constraints.
- Do not implement stealth behavior.
- Prefer explicit, inspectable behavior and logs.
- Default to local storage only.
- Avoid writing to cloud-synced directories by default unless explicitly configured.

## Tech Choices (v1)

- Language: Swift
- Platform: macOS app/agent
- Deployment target: macOS 13+
- Camera: AVFoundation one-shot still capture
- Event triggers:
  - On launch: capture once (`session-open`)
  - On unlock/session active: capture once (`unlock`)
  - Debounce repeated OS signals
- Config: YAML (prefer `Yams`)
- Metadata sidecar: JSON (`Codable`)
- Logging: `os.Logger`
- Concurrency: async/await (structured concurrency)
- Packaging: menu-bar/agent style app (`LSUIElement=1`), optional menu bar icon

## Repository Structure (target)

- `LoginShotApp/`
  - `App/` (entrypoint, lifecycle, optional menu bar)
  - `Capture/` (camera access + one-shot capture)
  - `Triggers/` (session-open + unlock observers)
  - `Config/` (load/parse/defaults/path expansion)
  - `Storage/` (filenaming, atomic writes, sidecar JSON)
  - `Util/` (debounce, clock/time helpers, logging helpers)
- `LaunchAgent/` (plist + install/uninstall scripts; likely v1.1)

Agents may scaffold this structure as needed.

## Functional Requirements

### One-shot capture
- Capture one still image quickly.
- Release camera resources after capture.
- Handle failures gracefully (log + continue, no crash).

### Triggers
- Capture once on app launch (`session-open`).
- Capture once per unlock/session-active event (`unlock`).
- Debounce interval configurable (default `3` seconds).

### Storage
- Ensure output directory exists (create if missing).
- Filename format: `YYYY-MM-DDTHH-mm-ss-<event>.<ext>`
- Write files atomically (temp + rename/move).
- Write sidecar metadata JSON (`.json`) with same basename.

### Configuration
- Read from (first found wins):
  1. `~/.config/LoginShot/config.yml`
  2. `~/Library/Application Support/LoginShot/config.yml`
- Expand `~` to user home.
- Provide safe defaults.
- Validate config and fail with clear diagnostics.

### UI
- Menu bar icon optional via config.
- If enabled, include:
  - `Capture now`
  - `Open output folder`
  - `Reload config`
  - `Quit`

## Build / Lint / Test Commands (keep updated)

Choose commands based on project files present.

### Xcode workflow (preferred when `.xcodeproj` exists)
- Build:
  - `xcodebuild -scheme LoginShot -configuration Debug -destination 'platform=macOS' build`
- Test all:
  - `xcodebuild -scheme LoginShot -destination 'platform=macOS' test`
- Test a single test case:
  - `xcodebuild -scheme LoginShot -destination 'platform=macOS' -only-testing:LoginShotTests/<TestCase>/<testMethod> test`
- Test a single test class:
  - `xcodebuild -scheme LoginShot -destination 'platform=macOS' -only-testing:LoginShotTests/<TestCase> test`
- List schemes:
  - `xcodebuild -list -project LoginShot.xcodeproj`

### SwiftPM workflow (if `Package.swift` exists)
- Build:
  - `swift build`
- Test all:
  - `swift test`
- Test a single test:
  - `swift test --filter <TargetOrSuite>/<TestCase>/<testMethod>`
- Verbose test logs:
  - `swift test -v`

### Lint/format (if configured)
- SwiftLint:
  - `swiftlint`
  - `swiftlint --fix` (only when safe)
- SwiftFormat:
  - `swiftformat .`

If lint tools are not configured, follow existing style in touched files and avoid broad formatting churn.

## Coding Standards

### Imports
- Import only what is used.
- Keep imports at file top.
- Prefer deterministic ordering (alphabetical).
- Avoid adding heavy frameworks in shared utility files.

### Formatting
- Prefer repository formatter/linter config when present.
- Use consistent indentation and spacing.
- Keep functions focused and readable.
- Avoid unrelated reformatting in functional diffs.

### Types and API Design
- Prefer `struct` and `enum` unless reference semantics are required.
- Use protocols for test seams around camera/events/filesystem.
- Keep access control explicit (`private`, `fileprivate`, `internal`).
- Use strong domain types for events/config values over raw strings.

### Naming
- Types: `UpperCamelCase`
- Functions/properties/variables: `lowerCamelCase`
- Enums/cases should be domain-descriptive (`sessionOpen`, `unlock`)
- Tests should clearly state behavior and expectation.

### Error Handling
- Prefer typed `Error` enums with actionable cases.
- Use `throws` for recoverable failures.
- Avoid `try!` and force unwraps in production code.
- Avoid `fatalError` on user/system paths; log and continue safely.
- Include context in logs (event, path, subsystem state).

### Concurrency / State
- Use structured concurrency where appropriate.
- Avoid data races around trigger handling and debounce.
- Keep mutable shared state minimal and explicit.
- Ensure capture pipeline can fail independently without taking down the app.

### File I/O and Metadata
- Use atomic writes for image + sidecar where possible.
- Keep sidecar schema stable and backwards-compatible.
- Ensure output folder and permissions are validated before capture write.

## Testing Expectations

- Add tests for all behavior changes.
- Prioritize unit tests for:
  - Config parsing + defaults
  - Path expansion
  - Filename formatting
  - Debounce logic
  - Metadata sidecar generation
- Prefer deterministic tests with mocks/fakes for camera and clock.
- Add integration/dev harness only when needed (e.g., debug trigger).

## Rules Files (Cursor / Copilot)

None present at time of writing. If `.cursorrules`, `.cursor/rules/`, or `.github/copilot-instructions.md` are added, agents must read and follow them before making edits.

## Agent Workflow

- Read nearby code and mirror local patterns.
- Make the smallest correct change first.
- Run targeted/single tests before full suite.
- Update `README.md` for user-visible behavior/config changes.
- Do not revert unrelated working tree changes.
- Do not use destructive git operations unless explicitly requested.

## Repository Hosting and Collaboration Model

- Canonical remote is GitHub: `https://github.com/pruiz/LoginShot`.
- Treat this repository as PR-driven: all meaningful changes should flow through feature branches and pull requests.
- Default branch is `master` and should be treated as protected and long-lived.
- Agents should align with existing branch protection and review requirements when present.

## Branching Policy

- Never commit directly to `master`.
- Never push directly to `master`.
- Always work on a non-default branch for code, tests, docs, and refactors.
- Preferred branch names:
  - `feature/<short-description>`
  - `task/<short-description>`
  - `fix/<short-description>`
  - `docs/<short-description>`
  - `test/<short-description>`
- Keep branch scope focused; avoid mixing unrelated changes.
- Forbidden without explicit instruction: force push to `master`, destructive history edits (`reset --hard`, unsafe rebases) on shared branches.
- If currently on `master`, create/switch to a feature branch before making edits.

## Pull Request Workflow

- Open a PR for any change intended to merge.
- PRs should include:
  - Clear title (concise, imperative).
  - Why the change is needed.
  - What changed (high-level bullets).
  - Test evidence (commands run and outcomes).
  - Risks/rollout notes when applicable.
- Keep branch updated from `master` regularly to reduce drift/conflicts.
- Do not self-merge unless explicitly instructed and repository policy allows it.
- Prefer small PRs that are easy to review.

## Commit and Push Rules for Agents

- Do not create commits unless explicitly requested by the user/task.
- When committing, keep commits atomic and logically scoped.
- Use descriptive commit messages focused on intent.
- Never use force push (`--force` or `--force-with-lease`) unless explicitly instructed.
- Never rewrite published history unless explicitly instructed and safe.
- Do not amend commits after push unless explicitly requested.
- Never bypass hooks with `--no-verify` unless explicitly requested.
- Never commit secrets, credentials, tokens, or local environment files.

## Suggested Development Workflow for Agents

1. Sync and inspect branch status.
2. Create/use a non-default branch (`feature/...` or `task/...` as appropriate).
3. Make the smallest correct change.
4. Run targeted tests first, then broader tests as needed.
5. Run lint/format if configured.
6. Prepare concise commit(s) when requested.
7. Push branch and open/update PR with summary + test evidence.
8. Address review feedback with incremental commits.

## CI and Merge Expectations

- Ensure CI passes before merge (build/test/lint per repository policy).
- If CI fails, fix root cause before requesting merge.
- Prefer squash merge unless project policy specifies otherwise.
- After merge, clean up branches according to repository conventions.

## Notes / Pitfalls

- Camera permission (TCC) is tied to app identity and bundle execution.
- Unlock/session notifications vary across macOS versions; use layered observers if needed.
- Keep behavior transparent and auditable.

## Out of Scope (v1), possible future

- Signing/notarization/MDM deployment
- Cloud API uploads
- Face recognition or identity classification
- Retention/deletion policy automation
