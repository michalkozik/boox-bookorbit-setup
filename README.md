# boox-bookorbit-setup

A [Claude Code](https://claude.com/claude-code) skill that sets up an **Onyx Boox** e-ink reader
as a dedicated BookOrbit + [KOReader](https://github.com/koreader/koreader) device:

- **Home press opens KOReader** (a tiny launcher, `koho`, replaces the stock Boox home screen).
- KOReader opens the **BookOrbit dashboard** at start (continue reading, recently added, streak).
- **One book folder** (`/sdcard/Books`) used as KOReader home and BookOrbit download dir.
- **Reading progress, status and highlights sync** with your BookOrbit server.
- A strict **"don't touch my notes" protocol**: back up first, no destructive commands.

It drives everything over `adb` from your computer; you stay in the loop for the few things only the
device UI can do (developer mode, backup, disabling Boox app auto-freeze).

> **Status:** built and verified on a Boox **Go 6** (Android 11, firmware 4.2). A **Note Air 5C**
> (Android 15) was only inventoried, not configured. Anything marked *untested* in the skill is a plan,
> not a result. Not affiliated with Onyx, BookOrbit or KOReader.

## Install the skill

```bash
git clone https://github.com/michalkozik/boox-bookorbit-setup.git
cp -R boox-bookorbit-setup/skills/boox-bookorbit-setup ~/.claude/skills/
```

Restart Claude Code. The skill loads on its own when you mention Boox, KOReader or BookOrbit on an e-ink
device. You can also invoke it by name.

## How to use it

1. Connect the Boox by USB (data cable, USB mode *File transfer*), enable developer options and
   *USB debugging*, accept the RSA prompt on the device.
2. In Claude Code, say something like:
   > Set up my Boox as a BookOrbit reader. Home should open KOReader with the BookOrbit dashboard.
   > My BookOrbit server is `https://books.example.com`.
3. Claude first does a **read-only inventory** and asks you to **back up your notes in the Notes app**
   (Notes → menu → Options → Backup and Restore). It will not change anything until you confirm.
4. It then installs KOReader, the BookOrbit plugin and the ZenOS interface, sets the book folder, builds
   and installs `koho`, makes it the default home app, and configures the dashboard autostart.
5. You do three things on the device: log in to the BookOrbit plugin, turn **off Boox auto-freeze** for
   KOReader and `koho` (Apps → App Management), and confirm what you see on screen.

Revert the launcher at any time, without touching data:

```bash
adb shell pm set-home-activity com.onyx/.StartupActivity
```

## What is in this repo

| Path | What |
|---|---|
| `skills/boox-bookorbit-setup/SKILL.md` | the procedure Claude follows |
| `skills/boox-bookorbit-setup/scripts/build-koho.sh` | builds the `koho` launcher APK (JDK + Android build-tools from Google) |
| `skills/boox-bookorbit-setup/scripts/rewrite-koreader-paths.py` | fixes book paths in KOReader state after moving books |
| `skills/boox-bookorbit-setup/assets/koho/` | launcher source (one activity, ~25 lines) |
| `docs/lessons-learned.md` | pitfalls and mistakes from the original setup |
| `docs/devices.md` | supported models and how to reach developer options on each |

No APK is shipped; build it yourself so you know what runs on your device.

## Safety, honestly

Boox Notes keeps notes in the app's private database. `adb` cannot read it, so **the skill cannot back
your notes up for you**; you must export them in the app. The skill avoids destructive operations
(`pm clear`, uninstall, factory reset, deleting outside the book folders) but **cannot guarantee**
data safety. Use at your own risk, with a verified backup stored off the device.

## Help support more devices

Boox menus differ per model and firmware (on the Go 6, developer options are reached through the Apps
tab and its hamburger menu; other models differ). If you set up a different model, please share the
exact path you used: see [docs/devices.md](docs/devices.md), the **Device report** issue template and
[CONTRIBUTING.md](CONTRIBUTING.md). Report what you tested and mark the rest as untested.

## Known limitations

- Boox **auto-freeze** disables third-party apps; it cannot be turned off over `adb`.
- **Project: Title** and **ZenOS** are mutually incompatible; the skill uses ZenOS.
- On Android 15 `pm set-home-activity` may be restricted (*untested*).
- "Notes in the launcher menu" is a design in `SKILL.md`, **not implemented**.
- Screenshots over `adb` do not work on Boox, so UI results need your confirmation.

## License

MIT, see [LICENSE](LICENSE).
