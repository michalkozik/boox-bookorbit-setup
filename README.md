# boox-bookorbit-setup

## Table of contents

- [Why BookOrbit: a bookshelf that stays at home](#why-bookorbit-a-bookshelf-that-stays-at-home)
- [Install the skill](#install-the-skill)
- [How to use it](#how-to-use-it)
- [What is in this repo](#what-is-in-this-repo)
- [Safety, honestly](#safety-honestly)
- [Help support more devices](#help-support-more-devices)
- [Known limitations](#known-limitations)
- [License](#license)

A [Claude Code](https://claude.com/claude-code) skill that sets up an **Onyx Boox** e-ink reader
as a dedicated [BookOrbit](https://bookorbit.app) + [KOReader](https://github.com/koreader/koreader) device:

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

## Why BookOrbit: a bookshelf that stays at home

[BookOrbit](https://bookorbit.app) ([source](https://github.com/bookorbit/bookorbit), AGPL-3.0) is a
self-hosted library and reading platform for ebooks, PDFs, audiobooks and comics. You run it yourself
(Docker, on a home server, NAS-adjacent box or VPS) and point it at a folder of your own files. Your
library, your reading progress, your highlights and your user accounts live on hardware you control,
not in a vendor's cloud account that can change terms, lose a catalogue or close.

What that gives an e-ink reader:

- **A KOReader plugin** with a catalog browser, download, and two-way sync of progress and annotations,
  plus **OPDS** and **Kobo sync** for other devices and apps.
- **Multi-user** with per-user permissions and isolated reading data, and **OIDC/SSO** support
  (Authentik, Keycloak, Authelia) so a household shares one shelf with separate accounts.
- **Open formats and plain files:** your books stay ordinary files in a folder you can back up, copy or
  move; nothing is locked into a proprietary reader.

Honest trade-offs: you run and update the server, and you back it up yourself. Metadata lookups can
contact external providers depending on your settings, and exposing the server to the internet (for
example through a tunnel or reverse proxy) means that traffic leaves your home network. If you keep it
on your LAN or behind a VPN, the library stays strictly at home. NAS network mounts (SMB/NFS) are not
supported by BookOrbit as a book path according to its README.

References:
- Website and docs: https://bookorbit.app, [What is BookOrbit](https://bookorbit.app/what-is-bookorbit),
  [Installation](https://bookorbit.app/installation)
- Source and license: https://github.com/bookorbit/bookorbit
- KOReader: https://github.com/koreader/koreader

## Install the skill

```bash
git clone https://github.com/michalkozik/boox-bookorbit-setup.git
cd boox-bookorbit-setup
git log -1 --format='%H %s'    # note the commit you reviewed; update on purpose, not blindly
cp -R skills/boox-bookorbit-setup ~/.claude/skills/
```

The skill folder is self-contained (procedure, scripts, references, pinned checksums, launcher source), so
nothing else needs to be copied. Read `SKILL.md` and the scripts before you let an agent run them: they
install apps on your device. Restart Claude Code. The skill loads on its own when you mention Boox, KOReader
or BookOrbit on an e-ink device. You can also invoke it by name.

**Host requirements:** macOS or Linux x86_64 (Windows via WSL), a JDK 11+ for building `koho`, and `adb`
(the skill points to the pinned Google platform-tools).

## How to use it

1. Connect the Boox by USB (data cable, USB mode *File transfer*), enable developer options and
   *USB debugging*, accept the RSA prompt on the device. Attach only that one device.
2. In Claude Code, say something like:
   > Set up my Boox as a BookOrbit reader. Home should open KOReader with the BookOrbit dashboard.
   > My BookOrbit server is `https://books.example.com`.
3. Claude first runs a **read-only preflight** (model, Android, ABI, storage, packages, current Home) and
   asks you to **back up your notes in the Notes app** (Notes → menu → Options → Backup and Restore). It pulls
   the backup and checks device and host SHA-256, and it will not change anything until you confirm.
4. It then installs KOReader, the BookOrbit plugin and the ZenOS interface, sets the book folder, builds
   and installs `koho`, makes it the default home app step by step, and configures the dashboard autostart.
   Before each change it re-checks that it is still talking to the same device.
5. You do three things on the device: log in to the BookOrbit plugin, turn **off Boox auto-freeze** for
   KOReader and `koho` (Apps → App Management), and confirm what you see on screen.

Revert the launcher at any time, without touching data (use the Home component that preflight recorded; on
Boox it is usually this one):

```bash
adb -s SERIAL shell pm set-home-activity com.onyx/.StartupActivity
```

## What is in this repo

| Path | What |
|---|---|
| `skills/boox-bookorbit-setup/SKILL.md` | the procedure Claude follows |
| `skills/boox-bookorbit-setup/scripts/preflight.sh` | read-only device check, binds work to one device |
| `skills/boox-bookorbit-setup/scripts/verify-notes-backup.sh` | pulls and hash-verifies the in-app Notes backup |
| `skills/boox-bookorbit-setup/scripts/build-koho.sh` | builds the `koho` launcher (pinned, checksum-verified toolchain, stable signing key) |
| `skills/boox-bookorbit-setup/scripts/rewrite-koreader-paths.py` | dry-run-first, validated path rewrite for KOReader state files |
| `skills/boox-bookorbit-setup/scripts/check-devices.py` | validates the device table |
| `skills/boox-bookorbit-setup/checksums.sha256` | pinned SHA-256 of downloaded toolchain archives |
| `skills/boox-bookorbit-setup/assets/koho/` | launcher source (one activity with a recovery chain) |
| `skills/boox-bookorbit-setup/references/devices.md` | supported models and how to reach developer options on each |
| `skills/boox-bookorbit-setup/references/lessons-learned.md` | pitfalls and mistakes from the original setup |
| `.github/workflows/ci.yml` | shellcheck, tests, device-table validation, launcher build |

No APK is shipped; build it yourself so you know what runs on your device. The `koho` signing key is created
on your machine in `~/.config/koho/` and must be kept: a different key makes `adb install -r` fail.

## Safety, honestly

Boox Notes keeps notes in the app's private database. `adb` cannot read it, so **the skill cannot back
your notes up for you**; you must run the in-app backup, and the skill then verifies the copied file is
intact (it cannot prove the backup is restorable, so also keep `.note` exports of irreplaceable notes). The
skill forbids destructive operations (`pm clear`, uninstall, factory reset, recursive deletes; it moves files
to a quarantine folder instead of deleting) but **cannot guarantee** data safety. Use at your own risk, with a
verified backup stored off the device.

Downloads of the Android toolchain are pinned by SHA-256. KOReader, its plugins and ZenOS are not pinned
here because they change; the skill tells the agent to record their hashes and check signatures.

## Help support more devices

Boox menus differ per model and firmware (on the Go 6, developer options are reached through the Apps
tab and its hamburger menu; other models differ). If you set up a different model, please share the
exact path you used: see [the device table](skills/boox-bookorbit-setup/references/devices.md), the
**Device report** issue template and [CONTRIBUTING.md](CONTRIBUTING.md). Report what you tested and mark the
rest as untested.

## Known limitations

- Boox **auto-freeze** disables third-party apps; it was not settable over `adb` on the tested firmware.
- **Project: Title** and **ZenOS** are mutually incompatible; the skill uses ZenOS.
- On Android 15 `pm set-home-activity` may be restricted (*untested*).
- "Notes in the launcher menu" is a design in `SKILL.md`, **not implemented**.
- Screenshots over `adb` do not work on Boox, so UI results need your confirmation.
- Native Windows hosts and Linux on ARM are not supported by the build script.

## License

MIT, see [LICENSE](LICENSE).
