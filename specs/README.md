# Leyne — internal specs

Internal documentation. Not served from the public `docs/` site.

- [`design-spec.md`](design-spec.md) — canonical UI/UX spec, derived from iOS-native (the lead platform). Source of truth for both platforms; when Flutter and the spec disagree, Flutter is behind.
- [`parity.md`](parity.md) — what's in iOS-native that Flutter Android hasn't caught up to. Work queue if/when Android is brought to design parity.

## How to use these

- **Implementing on iOS-native:** if your change introduces something not in `design-spec.md`, update the spec in the same PR. iOS-native is the lead platform, but the spec is the published artifact other implementations read.
- **Implementing on Flutter Android:** read `design-spec.md` first. If your task is in `parity.md`, mark the row ✅ when shipped.
- **Reviewing a design change:** if the change adds a new pattern, the PR should add or update a section in `design-spec.md`. No new patterns without a spec entry.
