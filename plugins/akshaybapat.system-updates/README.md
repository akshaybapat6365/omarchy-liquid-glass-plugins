# System Updates (`akshaybapat.system-updates`)

Unified Arch, AUR, Flatpak, Omarchy, mise, and shell add-on update indicator with expandable package lists, release-note links, and per-repo update buttons.

Derived from [JJDizz1L/dizziee.system-updates](https://github.com/JJDizz1L/dizziee.system-updates) (MIT) with three key reliability improvements: serialized `checkupdates` execution (fixing lock races between Arch and Omarchy checks), honest **Check failed** states (never silently reporting failed checks as "Up to date"), and E-core background scheduling (`os.sched_setaffinity` on hybrid CPUs).

<p align="center">
  <img src="preview.png" alt="System Updates panel" width="540">
</p>

## Highlights

- **6 Update Sources in One Panel** — Arch (`pacman`), AUR (`yay`/`paru`/`checkupdates-aur`), Flatpak, Omarchy core, shell plugins, and `mise`.
- **Safe Snapshot-Aware Upgrades** — Arch and Omarchy updates launch through `omarchy update` so Btrfs snapshots and keyring steps remain intact.
- **Zero Lock Races & Honest Failures** — Serializes Arch/Omarchy database checks and surfaces explicit failure indicators if a repo check cannot reach the network.
- **Thermally Quiet Background Scans** — Automatically pins background checks to efficiency cores (`/sys/devices/cpu_atom/cpus`) at idle priority when available.

## Install

```bash
../../install.sh --plugin system-updates --enable
```

## Settings

| Key | Default | Description |
| --- | --- | --- |
| `refreshIntervalSec` | `1800` | Automatic check interval (`300`–`7200` seconds) |
| `alwaysShow` | `true` | Keep the bar icon visible even when zero updates are pending |
| `autoRefresh` | `true` | Run background checks automatically on startup and interval |

## License

MIT — see [LICENSE](LICENSE). Copyright Dizziee (original) and Akshay Bapat (fork).
