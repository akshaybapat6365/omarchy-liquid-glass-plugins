# AI Usage (`akshaybapat.ai-usage`)

Every configured AI provider's quota at once, rendered as precision 22 px circular tachometer dials with centered vendor marks, pace ticks, and tabular figures right in the [Omarchy](https://omarchy.org) top bar — paired with a detailed expandable quota & local activity panel (`ui/v1_15_2`).

Derived from the Omarchy frontend of [akitaonrails/ai-usagebar](https://github.com/akitaonrails/ai-usagebar) (MIT). Credential storage and provider API calls stay solely inside the external `ai-usagebar` Rust binary; this plugin never reads or stores raw secrets.

<p align="center">
  <img src="preview.png" alt="AI Usage circular tachometer bar strip and panel (synthetic data)" width="100%">
</p>

## Highlights

- **All Providers Simultaneously** — Replaces single-provider mouse-wheel cycling with an at-a-glance strip of circular tachometer gauges so you immediately see which quota is burning fastest.
- **3-Tier Semantic Color Ladder** — Calm theme ink (`< 70%`), warm amber (`70–89%` or balance `< $5`), and contrast-solved urgent coral (`≥ 90%` or balance `< $1`), with a pace notch marking elapsed window time.
- **Dual Panel Views** — Click any provider cell to open its **Account Quota** view (session/weekly meters, reset timers, pace delta) or inspect 30-day **Local Activity** across all configured providers.
- **E-Core Background Refresh** — `ui/v1_15_2/background.sh` automatically pins background polls to efficiency cores via `/sys/devices/cpu_atom/cpus` (when present) at `nice -n 19` so background refreshes stay thermally silent.
- **Zero-Secret UI Boundary** — Strips any key prefixes before strings ever reach tooltips or the bar; settings input scrubs passwords on close.

## Install

```bash
../../install.sh --plugin ai-usage --enable
```

Requires the upstream [`ai-usagebar`](https://github.com/akitaonrails/ai-usagebar) binary in your `PATH` configured with whichever providers you use.

## Settings

Configure via `omarchy bar set akshaybapat.ai-usage <key> <value>` or `~/.config/omarchy/shell.json`:

| Key | Default | Description |
| --- | --- | --- |
| `refreshIntervalSec` | `300` | Background refresh interval (`30`–`3600` seconds) |
| `showPercent` | `true` | Show tabular usage figure beside each circular dial |
| `showMeter` | `true` | Draw circular tachometer ring and pace tick around each mark |
| `compact` | `false` | Dials and marks only for compact bars |
| `providers` | `""` | Optional comma-separated filter & order (e.g. `anthropic,openai,cursor`) |

## License

MIT — see [LICENSE](LICENSE). Copyright Fabio Akita / AkitaOnRails (original) and Akshay Bapat (fork). Vendor marks retain their respective trademarks / Simple Icons CC0 attributions (see [LICENSE](LICENSE)).
