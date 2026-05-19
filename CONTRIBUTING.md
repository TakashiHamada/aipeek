# Contributing to AIPeek

Thanks for thinking about contributing! AIPeek is small and focused — *drawings to AI in one paste* — and contributions that align with that core loop are most welcome.

This guide is short on purpose. If anything is unclear, open an issue and ask.

## Ways to contribute

- 🐛 **Bug reports** — including reproducible UI / drawing issues
- 💡 **Feature requests** — please keep them motivated by a real workflow you have
- 📝 **Documentation** — README polish, an English translation of `CLAUDE.md`, inline code comments
- 📸 **Visuals** — screenshots, demo GIFs (see [Adding screenshots](#adding-screenshots))
- 🔧 **Code** — bug fixes and small features (please open an issue first for anything non-trivial)

## Filing issues

Useful information for bug reports:

- macOS version (e.g. macOS 14.4 on Apple Silicon)
- AIPeek version (Releases tag, or commit hash if built from source)
- Steps to reproduce
- What you expected vs. what happened
- A screenshot of the canvas if the issue is visual

For feature requests, please describe the workflow you're trying to support — "I want X so I can do Y" is much easier to act on than "Add X".

## Submitting pull requests

1. **Fork** the repo and create a topic branch off `main`. Branch naming: `fix/short-description` or `feat/short-description`.
2. Make your change in **small, focused commits**. Match the existing code style.
3. **Build cleanly** on a fresh `xcodebuild ... build` (see [Build](#build) below). Try to keep warnings to a minimum; flag any you can't easily remove in the PR description.
4. **Test the affected flow on a real Mac**. PencilKit + Mac Catalyst behaviours don't reliably reproduce in Xcode previews — the canvas, Shift snap, clipboard, auto-save, and undo paths all need a running app to validate.
5. Open a PR with:
   - A one-line summary
   - A short *why* paragraph
   - Any UI changes captured as screenshots / GIFs
   - A short test plan (what you actually clicked / drew / typed)

The repository currently has GitHub Copilot Code Review enabled, so an automated review pass usually shows up within a few minutes of opening the PR. Please address or explicitly acknowledge each comment in the thread.

### Build

```sh
# Debug
xcodebuild -project Sketch.xcodeproj -scheme Sketch \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' build

# Release
xcodebuild -project Sketch.xcodeproj -scheme Sketch \
  -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' build
```

## Coding style

Plain Swift, with the project's existing conventions:

- 4-space indent.
- `final class` by default.
- `private` / `fileprivate` where reasonable.
- Comment the **why**, not the **what**. PencilKit / Mac Catalyst quirks deserve a few lines of explanation — the next person to touch the file (often the same person, three months later) will thank you.
- No external dependencies. AIPeek deliberately stays on the system frameworks.

## Design rationale

A lot of the canvas behaviour is shaped by non-obvious PencilKit and Mac Catalyst limitations. Before changing canvas internals, please skim [`CLAUDE.md`](CLAUDE.md) — particularly the *重要な設計判断* (important design decisions) section and the *Review Checklists* — to avoid re-discovering known traps such as:

- Why `drawingPolicy` is pinned to `.anyInput` (and *not* `.pencilOnly`)
- Why PencilKit's live preview is suppressed via `hitTest`, not by gesture toggling
- How the red marker's "below the black" look is implemented (z-order, not blend mode)
- Why Shift state is polled via `CGEventSource` + `CADisplayLink` on Catalyst

`CLAUDE.md` is currently written in Japanese. An English translation PR would be a great first contribution.

## Adding screenshots

The current hero asset is `docs/demo.gif`, embedded via the `<img>` block at the top of `README.md`. Additional visuals are welcome:

- **Replace `docs/demo.gif`** with a sharper / shorter recording (keep the same filename so the README picks it up automatically).
- **Add a still screenshot** at `docs/screenshot.png` (or any descriptive filename under `docs/`) and add a second `<img>` tag next to the existing one in the README hero block.

Tips:

- Record at the app's native size (~1000–1280 px wide); the README displays it at 720 px so high-DPI looks crisp.
- Keep GIFs under ~3 MB if possible.
- Tools that work well: [Kap](https://getkap.co/), [LICEcap](https://www.cockos.com/licecap/), `⇧⌘5` (macOS built-in recorder → convert the result with `ffmpeg`).

## Code of conduct

Be kind, assume good faith, and remember that we're making a small drawing app a little better. Disagreement is fine; rudeness isn't.

If something's off, or if you'd rather raise it privately, contact the maintainer via the email in the commit log.

---

Thanks again for being here. 🙏
