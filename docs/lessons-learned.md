# Lessons learned (Boox Go 6, Android 11, firmware 4.2)

## Environment
- `brew install --cask android-platform-tools` failed because `/opt/homebrew` was not writable.
  Downloading `platform-tools-latest-darwin.zip` from dl.google.com worked.
- Boox hides the developer-mode entry; on Go 6 there was no "Build number". Unlocking worked by
  repeatedly tapping rows on the About Device screen. Different firmware may differ.
- Empty `adb devices` plus empty `system_profiler SPUSBDataType` = cable, port or USB mode.
- `adb exec-out screencap` returns nothing useful on Boox; rely on the user's description or photos.

## Launcher
- `pm set-home-activity` only works for an enabled package. Packages installed over adb were
  `enabled=3` (disabled by user) until `pm enable` was run.
- Boox **auto-freeze** (`isAutoFreeze:true` in logcat) re-disables third-party apps, including
  KOReader and any custom launcher. Symptom: Home shows a chooser or the stock launcher. Fix: turn
  auto-freeze off per app in Apps → App Management (UI only).
- KOReader has no HOME intent filter, so it cannot be set as home directly. A launcher that only starts
  KOReader and finishes (`koho`) is the thin solution; falling back to the stock launcher when KOReader
  is unavailable keeps the device usable.
- Olauncher worked as an intermediate home screen but needs a second tap and shows empty slots until
  configured in its own UI (preferences are private, cannot be set over adb).

## KOReader state files
- Edit `settings.reader.lua`, `history.lua`, `bookorbit_sync_state.lua` only with KOReader
  force-stopped, otherwise it overwrites them on exit.
- Auto-execute profiles: profile in `settings/profiles.lua`, trigger in `settings.reader.lua` under
  `profiles_autoexec.Start`. An existing empty `profiles_autoexec = {}` must be replaced, not duplicated.
- ZenOS reports "Project: Title is not compatible"; delete one of them.

## BookOrbit sync
- Matching is by content hash (partial md5), not file path. Identical files match anywhere; compare
  full `md5` before declaring two files different (a wrong claim here cost time).
- The plugin's library sweep only covers books with local reading state; unread books get matched
  when opened or via "Recheck all book matches".
- Editing a book's status in the `.sdr` file does not stick; the server wins. Mark it finished through
  KOReader or the BookOrbit web UI, then sync.
- New server books are not pulled automatically; download from the plugin catalog or copy files.
- Plugin login is separate from OIDC. With OIDC, the account must be linked on the server;
  `allowLocalLinking` off means no e-mail based auto-match.

## Notes (Boox Notes app)
- Notes are in the app's private database, unreachable over adb. Back up inside the app
  (Options → Backup and Restore → `/sdcard/note/backup/local`) and verify the copy.
- Never `pm clear` / uninstall / reset while you hold unbacked notes.
