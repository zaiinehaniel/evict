# Disk tab: see what's eating the disk, clear it fast

Status: approved design · 2026-10-20

## Intent

Disk space on a Mac is precious, and it fills up quietly: people don't tidy
their Downloads, and programs leave caches and build products behind long after
anyone needs them. Evict already does this for memory ("what's open, what does
it cost, close it"). The Disk tab asks the same question about storage. It shows
what can go, how big it is, and lets you remove it in one click, picking item by
item when you want to keep something.

Evict's voice still applies: *it informs; you decide.* Nothing is removed
without a click.

## Goals

- Show free disk space and how much can be reclaimed, the moment the popover's
  Disk tab opens.
- List reclaimable space in two groups:
  - **App junk**: regenerable data that programs rebuild on their own.
  - **Your files**: things the user made or downloaded that are probably
    forgotten.
- One-click removal per category from the list ("clear fast").
- Open any category to see its items one by one, uncheck what to keep, and
  remove the rest.

## Non-goals

- No background scanning, no notifications, no low-disk alerts, no disk % in
  the menu bar. Scanning happens only when the Disk tab is shown. The user
  explicitly said they don't want it to nag.
- No automatic cleanup or rules (unlike memory's auto-evict).
- No system-level cleanup (`/Library`, `/System`, other users, Time Machine
  local snapshots, purgeable space).
- No duplicate finder and no full-disk treemap.

## Anti-goals

These would make the feature a failure even if it technically works:

- Removing anything the user didn't explicitly click to remove.
- Removing user files permanently by default.
- "Optimization scores", scary warnings, or upsell-style "your Mac is at risk"
  copy.
- Making the popover noticeably slower to open, or making the Memory tab worse.

## Decisions (made with the user)

1. **Placement: tabs.** The popover gets a segmented control,
   **Memory | Disk**, under the header (mockup option A). Each tab owns the
   whole popover body. The header gauge reflects the active tab: memory used
   for Memory, disk free for Disk (e.g. "412 of 994 GB free").
2. **Only when opened.** No alerts and no background work.
3. **Show, then delete fast.** Each category row has a direct action button.
4. **Both delete modes.**
   - App junk is **deleted permanently** (moving regenerable caches to the Trash
     frees nothing).
   - Your files go **to the Trash** on a normal click. **⌥-click deletes
     permanently**: while ⌥ is held, the button title changes to "Delete" and
     a small "⌥ deletes permanently" hint shows.
5. **Your files are in scope**, not only app junk.
6. **One by one: drill-in screen** (mockup option B). Clicking a category row
   replaces the popover body with that category's item list, with a
   "‹ Disk" back control. The screen has:
   - a checkbox per item, all checked by default, plus "Select all (N)"
   - sort by size (default) or age
   - per item: name, age ("8 months"), size
   - Space opens Quick Look, double-click reveals in Finder
   - a footer button "Move N to Trash · X GB" (⌥ → "Delete N · X GB"); for app
     junk, "Delete N · X GB"

## Calls I made (the user can still overrule these)

- **The last-used tab is remembered** (`@AppStorage`).
- **The last scan result is cached** and shown immediately when the tab opens,
  then refreshed in place. A subtle "Scanning…" indicator shows while the scan
  runs. The tab should never open empty after the first scan.
- **App junk categories drill in too**, broken down per item: DerivedData per
  project, caches per app, simulators per runtime. That way the user can keep,
  for example, the cache of the project they're working on.
- **Unchecked items are remembered.** An item the user unchecked (keyed by its
  path) stays unchecked in later scans, and is excluded from the row's
  one-click action. Kept items still show in the list and still count toward
  the category size, but not toward "can be reclaimed".
- **Xcode archives are in Your files, not App junk.** They aren't
  regenerable, so they go to the Trash and are never part of a bulk delete.
- **Bulk "Clear app junk" button** in the Disk tab footer (in place of
  "Evict idle apps"). It uses the same inline confirmation pattern as
  "Quit All" (`pendingConfirmation`): "Delete 17.3 GB of app junk?"
  Cancel / Delete. It never touches Your files.
- **Category row one-click actions** (Delete / Move to Trash) also confirm
  inline, the same way "Quit All" does, because they act on many items at once.
  Footer actions inside a drill-in screen don't need a second confirmation,
  because the user just reviewed the list.
- **Caches of running apps** are listed but marked "Open". They are unchecked
  by default and excluded from bulk actions, since deleting a cache under a
  running app can misbehave.
- Categories with nothing to reclaim are hidden. If both groups are empty, an
  empty state in the same spirit as memory's "Nothing overstaying." is shown,
  e.g. "Nothing to clear. Your disk has room to breathe."

## Categories (v1)

The thresholds are my calls and are easy to tweak.

**App junk** (permanent delete)

| Category | What | Breakdown in drill-in |
|---|---|---|
| Xcode build data | `~/Library/Developer/Xcode/DerivedData/*` | per project folder |
| Xcode device support | `~/Library/Developer/Xcode/*DeviceSupport/*` (re-downloaded when a device connects) | per OS version folder |
| iOS Simulators | unavailable simulator devices (`xcrun simctl list devices unavailable -j`, removed per device with `simctl delete <udid>`). Runtimes live in `/Library` and are out of scope | per device |
| Package manager caches | Homebrew (`brew --cache`), npm (`~/.npm/_cacache`), pip, yarn, pnpm, CocoaPods, Gradle, SwiftPM — only those that exist | per tool |
| App caches | `~/Library/Caches/*` (per folder, shown with the app's name and icon when the folder name resolves to a bundle ID). `com.apple.*` folders are not listed | per app |
| Docker | unused images and build cache. Works whenever Docker Desktop is installed, running or not (see "Docker" below) | 2 items: images, build cache |

**Your files** (Trash by default, ⌥ permanent)

| Category | What |
|---|---|
| Installers | `.dmg`, `.pkg`, `.iso`, and `.zip` files whose name looks like an installer, in Downloads and Desktop |
| Xcode archives | `~/Library/Developer/Xcode/Archives/*/*.xcarchive` older than 90 days (by creation date). Not regenerable, because they hold the builds used to submit and to symbolicate crashes, so they live here and go to the Trash |
| Old downloads | top-level entries in `~/Downloads` not used in 90+ days. "Used" means the latest of Spotlight's last-used date (`kMDItemLastUsedDate`, if any) and the modification date. For folders, the newest modification date inside |
| Large files | files > 1 GB anywhere in the home folder, subject to the "Never scanned" rules below and not inside a `node_modules` |
| Stale `node_modules` | `node_modules` folders whose project (the parent folder, excluding the `node_modules` itself) hasn't been modified in 60+ days, searched under the home folder, excluding `~/Library` and hidden folders |
| Trash | the user's Trash; the action is "Empty" (always permanent) |

An item appears in only one category. Precedence follows the table order
(Installers > Xcode archives > Old downloads > Large files > Stale
`node_modules`), and an item inside an already-listed folder isn't listed
again.

### Docker

Images live inside Docker Desktop's VM disk
(`~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`), and
only the Docker daemon can remove them. The user wants Evict to clean them
even when Docker is merely installed, and approved Evict starting and
stopping Docker for that.

- **Running:** sizes come from `docker system df --format json`. Cleaning
  runs `docker image prune -a -f --filter until=720h` (unused images older
  than 30 days, my call on "old") and `docker builder prune -f`.
- **Installed but not running:** the row shows the VM disk's allocated size,
  "Docker · 38 GB (not running)". That size isn't counted in "can be
  reclaimed", since the reclaimable share is unknown. The action is
  **"Open and clean"**: start Docker hidden (`open -g -a Docker`), wait for
  `docker info` to answer (time out after about 2 minutes with an inline
  error), prune as above, then quit Docker gracefully **only if Evict started
  it**. The row shows progress ("Starting Docker…", "Cleaning…").
- The drill-in shows the two items once Docker is running; while it's off,
  the row has no drill-in.
- Docker is never part of "Clear app junk", because starting an app isn't a
  side effect a bulk delete should have.
- The freed space is returned to macOS as the VM disk shrinks, which may not
  happen instantly. The row says what was cleaned, not a promised GB.
- Not installed (no `Docker.app` and no CLI): the category is hidden. If the
  CLI fails for any other reason, it shows an inline error on the row.

### Never scanned (the user asked: nothing from Drive, iCloud, or the OS)

- `~/Library` as a whole (this includes iCloud Drive in `Mobile Documents`
  and Google Drive/Dropbox/OneDrive in `CloudStorage`), except the specific
  App junk paths listed above
- Cloud sync folders at the home root: `~/Dropbox*`, `~/Google Drive*`,
  `~/OneDrive*`, `~/Box*`, `~/iCloud Drive*`
- Any item where `isUbiquitousItemKey` is true. This covers Desktop and
  Documents when "Desktop & Documents in iCloud" is on: those are skipped
  entirely.
- Hidden files and folders, packages (`.app`, `.photoslibrary`,
  `.musiclibrary`, `.fcpbundle`, any `isPackageKey` item), and symlinks
- Anything outside the home folder: `/System`, `/Library`, `/Applications`,
  `/usr`, other users, external and network volumes

### Permission opt-in for Your files

App junk is scanned as soon as the Disk tab opens, because it needs no
permission. **Your files is not scanned until the user clicks** a "Check your
files" row in that group, the user's choice. That click is what triggers the
macOS prompts for Downloads, Desktop and Documents. After it, Your files is
scanned automatically on every open. Until the click, nothing touches a
protected folder: the `node_modules` and Large files searches skip Downloads,
Desktop and Documents too. If a folder is denied, the group shows one row per
denied folder, "Allow access to Downloads in System Settings", which opens
Privacy & Security → Files and Folders. Denial is detected from the
permission error on the first directory listing.

## Item identity and selection

- Each item has a stable ID: its path for files and folders, `simctl:<udid>`
  for simulators, and `docker:images` / `docker:build-cache` for Docker.
- "Kept" state is keyed by that ID. A kept item stays kept (not re-evaluated
  against age or size rules) until it disappears from scans.
- The checked state in a drill-in screen and the row's one-click action use
  the same selection: everything not kept, minus running-app caches.
- The drill-in screen works on a snapshot. A background refresh doesn't
  reorder or remove rows while it's open, and the footer re-validates the
  selected items when the user clicks. The drill-in isn't restored after the
  popover closes; it reopens on the Disk overview.
- A cache is "Open" when its folder name matches the bundle ID of a running
  app. Folders that don't resolve are treated as not open.
- The `docker` binary is looked up in `/usr/local/bin`, `/opt/homebrew/bin`,
  `~/.docker/bin`, and `/Applications/Docker.app/Contents/Resources/bin`. The
  same applies to `brew` (the first two). `xcrun` is at `/usr/bin/xcrun`.
  There's no login shell PATH.

## Constraints

- **Platform:** macOS 14+, Swift 6, SwiftUI, `@Observable`, the same as the
  rest of the app. No new dependencies.
- **No sandbox.** `~/Library` is readable directly. **Downloads, Desktop and
  Documents are TCC-protected** (see "Permission opt-in for Your files"). No
  Full Disk Access is required, and nothing should ask for it.
- **Ad-hoc signing** (`CODE_SIGN_IDENTITY: "-"`) means TCC grants may be
  tied to each build's signature, so users could be re-prompted after every
  update. This is a known limitation; mention it in the README.
- **Safety:**
  - Only remove paths that come from the scan, under known roots. Never follow
    symlinks out of a root.
  - Re-check that each item still exists, and is still the same kind of item,
    right before removing it.
  - Trash via `FileManager.trashItem` (so Put Back works); permanent delete via
    `removeItem`.
  - For Docker and simulators, use their CLIs instead of deleting their files.
  - Report partial failures inline, e.g. "3 items couldn't be removed".
- **Size:** use allocated size (`totalFileAllocatedSizeKey`), the way Finder
  does. Free space: `volumeAvailableCapacityForImportantUsageKey` on the home
  volume.
- **Performance:** scan off the main actor. Scanning must never block the
  popover or the Memory tab's 3-second sampling. Categories fill in as they
  finish. Cancel the scan when the popover closes. `node_modules` and large
  file searches must skip `~/Library`, packages, and hidden system folders,
  and should stop descending into a `node_modules` once it's found.
- **Localization:** every string goes in `Localizable.xcstrings` for English
  and Português (Brasil).
- **Accessibility:** VoiceOver labels on rows, checkboxes, and icon-only
  buttons; Reduce Motion respected for the drill-in transition; Increase
  Contrast handled like `MemoryGauge`.
- **Style:** match the existing views (`BackgroundSection`, `AppRow`,
  `MemoryGauge`): 360 pt popover width, the same paddings, `Format` for sizes
  (add a disk-size formatter if `Format.memory` isn't appropriate), and Brand
  indigo for the disk bar. The bar turns orange below roughly 10% free.

## Persistence

- Remembered tab: `@AppStorage`.
- Kept (unchecked) paths and the last scan summary: `Preferences`, alongside
  `recentlyEvicted`. Prune kept paths that no longer exist.

## Left to the builder

- Code structure. A `DiskMonitor`, parallel to `AppMonitor` and owned by the
  same place, is the obvious fit, but that's the builder's call.
- How to resolve app names and icons for cache folders.
- Exact scan concurrency and ordering.
- README update (new feature bullet, TCC note) and screenshots via
  `ScreenshotRenderer` with demo data.

## Mockups

Selected options are in `.superpowers/brainstorm/` (gitignored):
`layout.html` (option A, tabs) and `files.html` (option B, drill-in).
