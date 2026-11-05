# Contributing

The most useful contribution is **device data**: Boox firmware differs a lot between models, and the
hardest part for a newcomer is simply getting to developer options and USB debugging.

## Add or correct a device
1. Read [docs/devices.md](docs/devices.md) and check whether your model and firmware are listed.
2. Open a **Device report** issue, or send a pull request that adds or fixes a row. Describe the
   developer-options path as the exact screens you tap (for example "Apps tab → hamburger menu → …").
3. Say what you actually tested. Mark anything you did not verify as *untested*. Wrong confident
   claims are worse than missing ones.

## Code and skill changes
- The procedure lives in `skills/boox-bookorbit-setup/SKILL.md`. Keep safety rules about the Notes
  app first and unchanged in strength: backup before any change, no `pm clear`, no uninstall,
  no factory reset.
- The launcher source is `skills/boox-bookorbit-setup/assets/koho/`. Keep it small; verify with
  `skills/boox-bookorbit-setup/scripts/build-koho.sh`.
- Do not commit APKs, keystores, serial numbers, account data or server URLs.
- Say in the pull request which device and firmware you tested on.

## Reporting data loss
If a step in the skill could destroy data on your device, open an issue marked **safety** straight away.
