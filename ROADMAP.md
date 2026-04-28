# Roadmap

Planned features beyond the current macOS/Linux build.

## Couples mode — partner target notifications

Let two linked accounts (you + your girlfriend) celebrate together.

- Pair two accounts via a short invite code or QR.
- When you hit a daily/period target, your partner gets a push: "Henrique
  hit his afternoon goal!" — and vice versa.
- Per-target opt-in (e.g. only daily total, not every period) so the pings
  don't get noisy.
- Optional reaction back ("clap", heart, custom emoji) that surfaces as a
  tray-icon flash on the sender's side.
- Quiet hours: respect each partner's idle/sleep window so notifications
  don't fire at 3 AM.

## Shared calendar view

A cute, two-person view of the existing per-day heatmap.

- Side-by-side or overlaid monthly grid: your squares on one side, hers on
  the other, with a subtle "both hit target" accent (heart / sparkle /
  pixel-art bloom) on days you both met your goals.
- Streak counters: solo streak, *joint* streak (consecutive days where you
  both hit target), and a "longest joint streak" trophy.
- Hover/tap a day to see both totals and which periods each of you
  completed.
- Theme pack: pastel + pixel-firework styling consistent with the existing
  celebration art. Optional "minimal" toggle for screenshots.

## Windows compatibility

A first-class Windows port alongside the existing macOS and Linux builds.

- Tray icon via a native Win32 `NOTIFYICONDATA` shell or a small Rust/C#
  wrapper — re-using the Linux Python core where possible.
- Idle detection via `GetLastInputInfo`.
- Launch-at-login via the `Run` registry key (HKCU) rather than a shortcut.
- Toast notifications via the WinRT `ToastNotification` API for target
  hits and partner pings.
- Installer: signed MSI or MSIX so SmartScreen doesn't block first-run.
- Parity goals: stopwatch toggle/reset, per-period targets, history
  calendar, fireworks (rendered with Direct2D or a transparent layered
  window), celebration sounds.

## Accounts & cross-device sync

A login layer so the same user has one timeline across machines.

- Email + magic-link or OAuth (Google / Apple) — no passwords if possible.
- End-to-end-ish sync of `prefs.json` and `history.json` to a hosted
  backend (Supabase / Firebase / a small self-hosted server — to be
  decided).
- Conflict resolution: last-writer-wins per `(day, hour)` bucket; the
  format already keys on those, so merges are cheap.
- Offline-first: local file remains the source of truth, sync is a
  background push/pull.
- Account is also what powers Couples Mode pairing above.

## macOS → Linux parity backport

Features that already exist on the upstream macOS (Tally) build but the
Linux port is missing. Backport these so both platforms stay in sync.

- **Live-refresh calendar / flush history every tick** — calendar window
  updates in real time as the timer ticks, instead of only when reopened.
- **Manual "Lock" button for daily goals** — replace the automatic
  start-of-day lock with an explicit user-controlled lock.
- **Lock daily goals after the first start of each day** — auto-lock
  fallback for the manual button (whichever fires first).
- **Spill excess period time into the next period** — once a period
  target is met, additional minutes count toward the next period instead
  of being "wasted".
- **App rename to "Tally"** — match upstream's product name across UI,
  launcher, autostart entry, and data directory paths.
- **Persist elapsed time on quit** — restart picks up where you left off,
  not just the daily total.
- **Install workflow polish** — match upstream's install/launch UX
  (signed/notarised on mac; equivalent .desktop / autostart polish on
  Linux).
- **Tightened idle-return prompt** — faster polling, tighter popover,
  "Keep" button resumes the timer instead of just dismissing.
- **Cmd/Ctrl+scroll on the tray icon to nudge the timer** — already
  noted as dropped on Linux due to tray-API limits; revisit with a
  modifier-key + global-hotkey alternative.
- **Bordered status-item label with adaptive monospaced format** —
  port the macOS status-bar look to the Linux tray rendering.
- **Block accidental quit** — only the menu's Quit item terminates the
  app; window-close / Ctrl+C don't kill the tray.
- **Blue squircle app icon** — adopt the upstream icon in place of the
  current Cairo-rendered placeholder for the launcher entry.

## Phone screen-time integration

Pull (or push) phone time so productivity apps used on mobile count toward
the daily target.

- **iOS**: read Screen Time data via the `DeviceActivity` /
  `FamilyControls` framework from a small companion app, then push
  selected app categories ("Productivity", or a user-curated allow-list)
  to the desktop timer over the account sync channel.
- **Android**: use `UsageStatsManager` (requires the "Usage access"
  permission) in a companion app to do the same.
- Manual mode: a "I worked N minutes on my phone" quick-add from the
  companion app for users who don't want to grant the OS permission.
- Mapping: phone minutes are added to the current period bucket on the
  desktop history, so per-period targets and the calendar heatmap reflect
  total focused time, not just desktop time.
- Privacy: only the *aggregate minutes per allowed app/category* leaves
  the phone — never raw app-usage logs or timestamps beyond the bucket
  resolution.
