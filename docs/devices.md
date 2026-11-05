# Supported devices

Boox firmware hides or moves settings between models and versions. This table collects what is known
to work, so the skill and users do not have to rediscover it. Contributions welcome, see
[CONTRIBUTING.md](../CONTRIBUTING.md).

Status: **verified** = full setup done and confirmed on the device, **partial** = some steps tried,
**untested** = no data.

| Model | Android | Firmware | Status | Developer options path | Notes |
|---|---|---|---|---|---|
| Boox Go 6 | 11 | 2026-05-25 (4.2) | verified | Apps tab, then the hamburger menu (reported by the device owner; the exact tap target was not recorded) | Stock About Device has no "Build number". `pm set-home-activity` works. Auto-freeze must be turned off in App Management. |
| Boox Note Air 5 C | 15 | 2026-08-03 (4.2.1) | partial | Enabling USB debugging worked; the exact path was not recorded | Read-only inventory only. `adb` sees `/sdcard/note` as almost empty (notes are in the app's private DB), Notes backup lands in `/sdcard/note/backup/local`. `pm set-home-activity` **untested** on Android 15. |

## How to add your device

Open a "Device report" issue (template provided) or send a pull request adding a row. Please include:

1. Exact model and firmware (Settings → About Device → Version).
2. Android version (`adb shell getprop ro.build.version.release`).
3. **Step-by-step path to developer options and USB debugging**, written as the screens you tap,
   because this differs per model and firmware.
4. Whether `pm set-home-activity io.github.michalkozik.koho/.Home` worked, and the output of
   `adb shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME`.
5. Where the Notes app backup lands and whether the backup menu names match the README.
6. Anything that behaved differently (auto-freeze, storage permissions, color screens).

Do not include serial numbers, MAC addresses, account names or server URLs.
