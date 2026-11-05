# Supported devices

Boox firmware hides or moves settings between models and versions. This table collects what is known
to work, so the skill and users do not have to rediscover it. Contributions welcome, see
[CONTRIBUTING.md](../../../CONTRIBUTING.md). `scripts/check-devices.py` validates this file in CI.

Status: **verified** = full setup done and confirmed on the device (requires a developer-options path and a
launcher result other than untested), **partial** = some steps tried, **untested** = no data.

| Model | Android | ABI | Display | Firmware | Status | Developer options path | Launcher step | Notes |
|---|---|---|---|---|---|---|---|---|
| Boox Go 6 | 11 | arm64-v8a | monochrome | 2026-05-25 (4.2) | verified | Apps tab, then the hamburger menu (owner report; exact tap target not recorded) | `pm set-home-activity` worked | Stock About Device has no Build number. Auto-freeze must be turned off in App Management. |
| Boox Note Air 5 C | 15 | arm64-v8a | color (Kaleido) | 2026-08-03 (4.2.1) | partial | USB debugging enabled; exact path not recorded | untested | Read-only inventory only. adb sees `/sdcard/note` almost empty (notes are in the app's private DB); Notes backup lands in `/sdcard/note/backup/local`. Color contrast and refresh behaviour untested. |

## How to add your device

Open a "Device report" issue (template provided) or send a pull request adding a row. Please include:

1. Exact model and firmware (Settings -> About Device -> Version).
2. Android version (`adb shell getprop ro.build.version.release`) and ABI list
   (`adb shell getprop ro.product.cpu.abilist`).
3. Display type (monochrome or color/Kaleido) and, for color, readability and refresh observations.
4. **Step-by-step path to developer options and USB debugging**, written as the screens you tap, because this
   differs per model and firmware.
5. Whether `pm set-home-activity io.github.michalkozik.koho/.Home` worked, plus the output of
   `adb shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME`.
6. Where the Notes app backup lands and whether the backup menu names match the skill.
7. Anything that behaved differently (auto-freeze, storage permissions, sleep/wake, reboot).

Do not include serial numbers, MAC addresses, account names or server URLs.
