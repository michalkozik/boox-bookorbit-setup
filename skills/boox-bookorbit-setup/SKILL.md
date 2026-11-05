---
name: boox-bookorbit-setup
description: Set up an Onyx Boox e-ink reader (Go 6, Note Air 5C and similar) so Home opens KOReader with the BookOrbit dashboard, books live in one folder, reading progress syncs with a BookOrbit server, and local Boox Notes stay untouched. Use when the user wants to configure a Boox as a BookOrbit/KOReader device, change its default launcher, repeat the Go 6 setup on another Boox, or put the Notes (drawing) app next to the reader. Triggers - Boox, Onyx, KOReader, BookOrbit on e-ink, launcher on Boox, Note Air.
---

# Boox + KOReader + BookOrbit setup

Goal state (verified on Boox Go 6, Android 11, firmware 4.2, 2026-11-01):
- Home press opens KOReader (via `koho`, a tiny launcher), KOReader opens the BookOrbit dashboard.
- One book folder (`/sdcard/Books`) = KOReader home dir = BookOrbit download dir.
- Auto sync with the BookOrbit server (progress, status, highlights).
- Zero changes to the Boox Notes app data.

Reply in the user's language. Work over `adb` from the computer.

`SKILL_DIR` below is the directory that contains this SKILL.md (the "base directory" shown when the
skill loads). Always call helpers by absolute path, `"$SKILL_DIR/scripts/<name>"`, never relative to the
current directory. Supporting material lives inside the skill: `references/lessons-learned.md`,
`references/devices.md` (known models and developer-options paths), `checksums.sha256`, `assets/koho/`.

## 0. Hard safety rules (notes have no sync, single copy on the device)

1. **No destructive commands.** Never run `pm clear`, `pm uninstall`, `pm disable-user`, factory reset
   or a system update on a device with notes. Never run recursive deletes (`rm -r`/`rm -rf`), especially
   on the roots `/sdcard/Books`, `/sdcard/Download`, `/sdcard/koreader`, or with an unchecked variable.
   Instead of deleting, **quarantine**: after a host backup, `mv` the exact file or folder to
   `/sdcard/koho-quarantine/<date>/` and tell the user it can be removed later by hand.
2. **Notes backup is the gate.** Notes live in the private database of `com.onyx.android.note`; `adb pull`
   and `run-as` cannot read it. The user must run Notes -> menu -> Options -> Backup and Restore -> Backup
   (menu names unverified per model). Then run
   `"$SKILL_DIR/scripts/verify-notes-backup.sh" -s SERIAL ~/boox-backups/<date>` which pulls
   `/sdcard/note/backup/local`, compares device and host SHA-256, and writes a manifest with timestamps.
   It proves the copy is intact, not that it is restorable: also ask for `.note` exports (Share and Export)
   of irreplaceable notes and never test a restore over the only live data. Stop if it fails.
   Source: https://shop.boox.com/blogs/news/backing-up-and-restoring-your-notes
3. **No change before the gate passes.** Do not start any mutating step until the backup manifest exists
   and the user confirmed. Say plainly that data safety cannot be guaranteed, only risk reduced.
4. **Bind every command to one device.** Run `"$SKILL_DIR/scripts/preflight.sh" [-s SERIAL]` first (read-only),
   record the IDENTITY line, and use `adb -s SERIAL ...` for everything. Before each mutating step run
   `preflight.sh -s SERIAL --expect-fingerprint FP`; stop if it fails. Detach other devices (emulators too).
5. **Snapshot before editing** books, `/sdcard/koreader/settings`, `settings.reader.lua` and `history.lua`
   to a dated folder on the host outside any git checkout (private permissions). Edit KOReader state
   only while KOReader is stopped (`am force-stop org.koreader.launcher`).
6. **Secrets.** Never print tokens, passwords or whole settings files (the plugin's section holds server
   and login data). Use HTTPS only for the BookOrbit server, never bypass TLS checks. The user logs in on the
   device. Keep backups, logs and reports out of any git repo; never put server URLs, accounts, serials or
   MAC addresses in public text.

## 1. Host tools

- macOS and Linux x86_64 are supported; on Windows use WSL (USB passthrough is yours to solve).
- adb: download the pinned platform-tools from `https://dl.google.com/android/repository/`
  (`platform-tools_r37.0.1-darwin.zip` or `-linux.zip`), check its SHA-256 against `checksums.sha256`, unpack to
  `~/.local/platform-tools`, run `~/.local/platform-tools/adb` (set `ADB=` for the scripts). `brew` casks may
  fail on non-writable prefixes.
- Developer mode: see `references/devices.md` for the model; otherwise Settings -> About Device and tap
  version-like rows 7 times, then Developer options -> USB debugging. Data cable, USB mode File transfer, accept
  the RSA prompt. Empty `adb devices` plus empty USB listing = cable/port/USB mode. Fallback: Wireless debugging.

## 2. Preflight (read-only)

`"$SKILL_DIR/scripts/preflight.sh"` prints model, Android/API, ABI list, storage, packages, current HOME and
existing books. Requirements: API >= 24. Pick the KOReader APK from `ro.product.cpu.abilist` (arm64-v8a or
armeabi-v7a), not by assumption. Existing books in `/sdcard/Books` are reused; delete nothing.

## 3. KOReader + plugins

- Download KOReader (official release matching the ABI), the BookOrbit plugin (from the server) and ZenOS
  (`xZenLabs/zen-os`, v4.2.0 worked) over HTTPS. Record each file's SHA-256, compare it with the digest the
  release page shows when it publishes one, and check APK signatures with `apksigner verify --print-certs`
  before `adb -s SERIAL install -r`. No vendor checksums are pinned in this repo (versions move);
  say so to the user.
- BookOrbit plugin: "Login to BookOrbit" with the account for this device, typed by the user. It logs in with
  its own credentials, not via OIDC; with OIDC, the BookOrbit account must be linked on the server
  (`allowLocalLinking` off means no e-mail based auto-match).
- ZenOS: copy `zenos.koplugin` into `/sdcard/koreader/plugins/`. It is incompatible with Project: Title; if
  `projecttitle.koplugin` exists, quarantine it (rule 0.1). First start shows a Home Folder wizard: choose
  "different folder" and long-press `/sdcard/Books` to select it.
- **Storage check before migrating:** inside KOReader open a book from `/sdcard/Books`, download one from the
  catalog, close and reopen KOReader and confirm progress persisted. adb visibility does not prove KOReader
  can write there (Android 11+ storage permissions). Fix permission first.

## 4. One book folder, sync-safe

- `home_dir` and `download_dir` in `settings.reader.lua` = `/storage/emulated/0/Books`.
- BookOrbit matches a file to the server by content hash (partial md5), not path. Server downloads of books
  with no series/author folder land in `Books/Standalone/`.
- Duplicates: compare full `md5` of both files. If identical, keep one **and keep both `.sdr` folders**; show the
  user the differences (percent finished, status, annotation count) and merge only fields they approve.
  Identical bytes do not make reading states interchangeable. Quarantine, do not delete.
- **State-edit transaction** (when books moved): (a) recovery HOME active, KOReader stopped; (b) snapshot and
  hash every affected file on host; (c) pull copies to a workdir outside git; (d) dry-run
  `"$SKILL_DIR/scripts/rewrite-koreader-paths.py" WORKDIR --map OLD NEW` and show the user the changes;
  (e) rerun with `--apply` (it backs up, validates, aborts on collisions); (f) push files back, verify each
  pushed hash against the host copy; (g) restart KOReader only after verification. On any failure restore the
  snapshot. The script never deduplicates; resolve collisions by hand.
- Do not set "finished" by editing `.sdr`; the server overwrote it. Use KOReader "Mark as finished" or the web UI.
- New server books are not pulled automatically: Open BookOrbit -> book -> Download (or copy files in).
- `auto_sync = true` syncs on open/close/wake/sleep/Wi-Fi connect and queues offline.

## 5. Home -> KOReader (launcher)

Boox auto-freezes (disables) third-party apps (`isAutoFreeze` in logcat); a frozen KOReader or koho makes
Home fall back to the Boox launcher or a chooser. The user must turn auto-freeze off for KOReader and `koho`
in Apps -> App Management (observed: not settable over adb on tested firmware).

Build and install (the signing key is created once in `~/.config/koho/` and must be kept):
```bash
"$SKILL_DIR/scripts/build-koho.sh"            # -> ~/.cache/koho-build/koho.apk; verifies pinned toolchain checksums
```
Then, one command at a time, checking each result (`ADB="adb -s SERIAL"`):
1. Save the original: `$ADB shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME | grep -m1 name`
   and `dumpsys package <pkg> | grep enabled=` for KOReader and koho.
2. `$ADB install -r ~/.cache/koho-build/koho.apk`
3. `$ADB shell pm enable io.github.michalkozik.koho` and `... pm enable org.koreader.launcher` (check "new state: enabled").
4. Launch both explicitly: `am start -n io.github.michalkozik.koho/.Home` and KOReader; confirm they open.
5. Only then `$ADB shell pm set-home-activity io.github.michalkozik.koho/.Home`; verify with the resolve-activity command.
6. Ask the user to test Home, a sleep/wake cycle and a reboot; re-check `enabled=1`.

Revert at any time (touches no data): `$ADB shell pm set-home-activity <saved original component>`
(on Boox usually `com.onyx/.StartupActivity`). koho's recovery chain if KOReader is unavailable: stock Boox
home, then system Settings. If `adb install -r` reports a signature mismatch, do not uninstall koho while it is
HOME: revert HOME first, then use the original key. Android 15 behaviour of `pm set-home-activity` is untested.

## 6. BookOrbit dashboard at KOReader start

Action id `bookorbit_open_dashboard` (registered by the plugin). With KOReader stopped, **merge** into existing
files, never replace them:
- `settings/profiles.lua`: add profile "BookOrbit start" with `["bookorbit_open_dashboard"] = true` and
  `settings = { name = "BookOrbit start", order = { "bookorbit_open_dashboard" } }`. Keep other profiles.
- `settings.reader.lua`: set `profiles_autoexec.Start["BookOrbit start"] = true`, keeping other entries
  (replace an empty `profiles_autoexec = {}`, do not add a second key).
- `adb screencap` returns nothing on Boox; the user confirms on screen.

## 7. Notes (drawing app) from the launcher menu

Design only, NOT built or tested. Do not claim it works.
- Notes app: `com.onyx.android.note`; find its launcher activity with
  `cmd package resolve-activity --brief -c android.intent.category.LAUNCHER com.onyx.android.note`.
- Plan "koho v2": Home opens KOReader; pressing Home while KOReader is on top (or a long press) shows a plain
  list of chosen apps launched with `getLaunchIntentForPackage`. No deep links into single notes (none known).
- Cheaper alternative: assign Notes to the Boox NaviBall (`com.onyx.floatingbutton`).
- Opening Notes must only launch the activity, never touch its data.

## 8. Verification

- HOME resolves to `io.github.michalkozik.koho.Home`; KOReader and koho `enabled=1` (3 = frozen by Boox).
- `settings/bookorbit_sync_state.lua` has a `bookId` per opened book and no stale paths.
- The server (or web UI) shows the progress; the notes backup manifest still exists on the host.
- `preflight.sh --expect-fingerprint FP` still matches the same device.

## 9. Offer to share device data

When the model/firmware is not in `references/devices.md`, offer to draft a device report (model, firmware,
Android, ABI, display type, exact developer-options path, launcher result, Notes backup path, per-feature
passed/failed/untested). Strip serials, MAC addresses, accounts and server URLs, show the draft, publish only if
the user agrees.
