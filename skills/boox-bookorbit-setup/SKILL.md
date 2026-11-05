---
name: boox-bookorbit-setup
description: Set up an Onyx Boox e-ink reader (Go 6, Note Air 5C and similar) so Home opens KOReader with the BookOrbit dashboard, books live in one folder, reading progress syncs with a BookOrbit server, and local Boox Notes stay untouched. Use when the user wants to configure a Boox as a BookOrbit/KOReader device, change its default launcher, repeat the Go 6 setup on another Boox, or put the Notes (drawing) app next to the reader. Triggers - Boox, Onyx, KOReader, BookOrbit on e-ink, launcher on Boox, Note Air.
---

# Boox + KOReader + BookOrbit setup

Goal state (proven on Boox Go 6, Android 11, firmware 4.2, 2026-11-01):
- Home press opens KOReader (via `koho`, a tiny launcher), KOReader opens the BookOrbit dashboard.
- One book folder (`/sdcard/Books`) = KOReader home dir = BookOrbit download dir.
- Auto sync with the BookOrbit server (progress, status, highlights).
- Zero changes to the Boox Notes app data.

Reply in the user's language. Work over `adb` from the computer. Lessons learned and mistakes made
during the original setup: `../../docs/lessons-learned.md`. Launcher source: `assets/koho/` (build it, no APK shipped).

## 0. Hard safety rules (notes have no sync, single copy on the device)

1. Never run `pm clear`, `pm uninstall`, `pm disable-user`, factory reset, or a system update on a
   device with notes. Never `rm` outside `/sdcard/Books`, `/sdcard/Download` and `/sdcard/koreader`.
2. Notes live in the private database of `com.onyx.android.note`. `adb pull` and `run-as` cannot
   reach it (verified on Note Air 5C, Android 15: `/sdcard/note` held only an empty `Text-1`).
   The user must back up inside the app: Notes -> hamburger menu -> Options -> Backup and Restore ->
   Backup. The file lands in `/sdcard/note/backup/local`; pull it to the Mac and compare file count
   and size. Single notes: Share and Export -> `.note`. Optional: ONYX Cloud. Source:
   https://shop.boox.com/blogs/news/backing-up-and-restoring-your-notes (menu names unverified on the device).
3. Do not start any change until the user confirms the backup and you verified the pulled copy.
4. State plainly that you cannot guarantee data safety, only reduce risk. Never claim a guarantee.
5. Back up everything you are about to edit (books, `/sdcard/koreader/settings`, `settings.reader.lua`,
   `history.lua`) to a dated folder on the Mac before editing. Edit KOReader state files only while
   KOReader is stopped (`am force-stop org.koreader.launcher`), otherwise it overwrites them on exit.

## 1. Connect adb

- No `brew`: `/opt/homebrew` was not writable. Use
  `https://dl.google.com/android/repository/platform-tools-latest-darwin.zip` unpacked to
  `~/.local/platform-tools` (run `~/.local/platform-tools/adb`).
- Developer mode: Settings -> About Device; Go 6 had no "Build number", the user unlocked it by tapping
  rows of that screen (Version, Model, Android Security Patch). Then Developer options -> USB debugging.
- Data cable, USB mode File transfer (MTP), accept the RSA prompt. Empty `adb devices` and empty
  `system_profiler SPUSBDataType` means cable, port or USB mode, not adb. Fallback: Wireless debugging.
- Only one device connected at a time.

## 2. Read-only inventory first

```bash
ADB=~/.local/platform-tools/adb
$ADB shell 'getprop ro.product.model; getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.product.cpu.abi; wm size'
$ADB shell 'cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME | grep -m1 name'
$ADB shell 'pm list packages -3; pm list packages | grep -i -E "koreader|olauncher|onyx.android.note"'
$ADB shell 'ls /sdcard; ls /sdcard/Books | head'
```
Note existing books in `/sdcard/Books` (Note Air 5C already had 28). Reuse that folder, delete nothing.

## 3. KOReader + plugins

- KOReader Android APK (arm64) from the official releases; install with `adb install -r`.
- BookOrbit plugin: install from the BookOrbit server (plugin menu has "Check for update"), then
  "Login to BookOrbit" with the account this device should use. The plugin logs in with its own
  credentials, not via OIDC. If the person uses Authentik/OIDC, check in the BookOrbit DB that the
  account is linked (`oidc_identities`); `allowLocalLinking` was off, so a local account is not
  auto-matched by e-mail.
- ZenOS (zen_ui.koplugin, repo `xZenLabs/zen-os`, v4.2.0 worked): put `zenos.koplugin` in
  `/sdcard/koreader/plugins/`. It is incompatible with Project: Title; use only one and delete
  `projecttitle.koplugin` if both exist.
- First launch of ZenOS shows a wizard with "Home Folder": choose "different folder" and pick
  `/sdcard/Books` (long-press the folder name to choose).

## 4. One book folder, sync-safe

- Home dir and download dir: `/sdcard/Books` (`home_dir`, `download_dir` in `settings.reader.lua`).
- BookOrbit matches a local file to the server by content hash (partial md5), not path, so identical
  files match in any folder. Server-fetched standalone books land in `Books/Standalone/`.
- When moving books, keep the `.sdr` folders (reading progress) next to them and rewrite paths with
  `scripts/rewrite-koreader-paths.py` on copies pulled from the device, KOReader stopped.
- Duplicates: compare full `md5` of both files before deleting. If identical, keep one, carry the
  newer `.sdr` metadata over.
- Do not set a finished status by editing `.sdr`; the server overwrote it. Use KOReader "Mark as
  finished" or the BookOrbit web UI, then sync.
- New books from the server are not pulled automatically: Open BookOrbit -> book -> Download, or copy
  files from the server's `/books` (docker cp from the `bookorbit-app` container) into `/sdcard/Books`.
- `auto_sync = true` in the plugin settings syncs on open, close, wake, sleep and Wi-Fi connect;
  without Wi-Fi it queues.

## 5. Home -> KOReader (launcher)

Boox auto-freezes (disables) third-party apps (`isAutoFreeze` in logcat). Frozen KOReader or launcher
makes Home fall back to the Boox launcher or a chooser. Ask the user to disable auto-freeze for
KOReader and `koho` in Apps -> App Management; it cannot be set over adb.

```bash
scripts/build-koho.sh                         # builds ~/.local/dl/koho-build/koho.apk
$ADB install -r ~/.local/dl/koho-build/koho.apk
$ADB shell 'pm enable io.github.michalkozik.koho; pm enable org.koreader.launcher; pm set-home-activity io.github.michalkozik.koho/.Home'
$ADB shell 'cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME | grep -m1 name'
$ADB shell 'am start -a android.intent.action.MAIN -c android.intent.category.HOME'   # test
```
Revert any time: `$ADB shell pm set-home-activity com.onyx/.StartupActivity` (touches no data).
Android 15 (Note Air 5C) is untested: `pm set-home-activity` may fail; then try the system default-home
chooser, or Olauncher (v6.9.17) as an intermediate, and say so.

## 6. BookOrbit dashboard at KOReader start

Action id `bookorbit_open_dashboard` (registered by the plugin). With KOReader stopped:
- `settings/profiles.lua`: profile "BookOrbit start" with `["bookorbit_open_dashboard"] = true` and
  `settings = { name = "BookOrbit start", order = { "bookorbit_open_dashboard" } }`.
- `settings.reader.lua`: `["profiles_autoexec"] = { ["Start"] = { ["BookOrbit start"] = true } }`
  (replace the existing empty `profiles_autoexec = {}`, do not add a second key).
- The user confirms on screen; `adb screencap` returns nothing on Boox.

## 7. Notes (drawing app) reachable from the launcher menu

Status: designed, NOT built or tested. Do not claim it works.
- The Boox Notes app is `com.onyx.android.note`. Find its launch activity with
  `$ADB shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER com.onyx.android.note`.
- Plan "koho v2": Home opens KOReader; Home pressed while KOReader is already on top (or a long press)
  shows a plain list of chosen apps (Notes, plus the user's other external apps) launched with
  `getLaunchIntentForPackage`. Add apps by package name in a small list in the source. No widget, no
  deep links into single notes (no known intent for opening a note by id; verify before promising it).
- Cheaper alternative needing no code: assign Notes to the Boox NaviBall (`com.onyx.floatingbutton`)
  shortcut, which works over any app.
- Opening Notes must never touch its data; only launch the activity.

## 8. Verification checklist

- `resolve-activity` for HOME returns `io.github.michalkozik.koho.Home`; KOReader and koho `enabled=1` in
  `dumpsys package` (enabled=3 means Boox froze them).
- BookOrbit sync state (`settings/bookorbit_sync_state.lua`) has a `bookId` per opened book and no old paths.
- The server shows the progress (`user_book_status`, `reading_progress` tables) or the user checks in the web UI.
- Notes backup still exists on the Mac and the Notes app was not touched.

## 9. Offer to share device data

When the setup ends on a model/firmware not listed in `docs/devices.md`, offer to draft a device report
for the user (model, firmware, Android version, exact path to developer options, whether the launcher
step worked, Notes backup path, what was tested vs untested). Remove serial numbers, MAC addresses,
accounts and server URLs first, show the draft, and publish it only if the user agrees.
