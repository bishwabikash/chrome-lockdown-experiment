# chrome-lockdown

Google Chrome enterprise policy for Linux that removes sign-in, sync, telemetry,
generative-AI features, and background network chatter — turning Chrome into a
plain browser with a minimal footprint.

Built for a Kali workstation where the browser is a tool, not an account.

Every policy key is verified against Chromium's own policy definitions by CI,
daily, on stable, beta and dev. See [Why the audit exists](#why-the-audit-exists).

## Scope

**Google Chrome only.** Policy goes to `/etc/opt/chrome/policies/managed/` and the
`-beta` / `-unstable` channel equivalents. Brave, Chromium, and Edge are
deliberately left alone.

Tested on Chrome **156** (Linux stable) and **158**; audited clean on both.

## Install

```bash
git clone https://github.com/bishwabikash/chrome-lockdown-experiment
cd chrome-lockdown-experiment
sudo ./install-chrome-lockdown.sh
```

Restart Chrome, then open `chrome://policy` and click **Reload policies**. Every
entry should read `OK`. Anything showing `unknown` or `error` is a bug — please
open an issue.

Optional flags:

| Variable | Effect |
| --- | --- |
| `BLOCK_EXTENSIONS=1` | Blocks all extension installs, including uBlock Origin. |
| `CLEAN_OTHER_BROWSERS=1` | Deletes this project's policy files from Brave / Chromium / Edge policy directories. Read the warning below first. |

### Throwaway profile

`chrome-ghost` launches Chrome with a fresh profile in `/dev/shm`, incognito, and
deletes it on exit:

```bash
sudo install -m 755 chrome-ghost /usr/local/bin/
chrome-ghost https://example.com
```

It refuses to run as root. Use an unprivileged user rather than reaching for
`--no-sandbox`.

## What it turns off

**Identity.** `BrowserSignin: 0` removes the sign-in path entirely — no avatar
button, no sync prompt, no profile picker. Sync, guest mode, and profile-add are
off too.

**Telemetry.** Metrics reporting, UKM, crash surveys, and the variations
framework. Variations matters most: left on, Chrome fetches a seed from Google on
every launch.

**Generative AI.** Sixteen policies covering AI Mode, Gemini actions, Help Me
Write, tab compare, voice typing, DevTools AI, and third-party AI chat. Notably
`GenAILocalFoundationalModelSettings: 1`, which blocks the on-device model
download — that model is roughly 4 GB on disk.

**Network chatter.** Omnibox suggestions, prefetch and preconnect, DNS-over-HTTPS,
Chrome's built-in DNS client, mDNS Cast discovery, cloud spellcheck, and translate.
QUIC is disabled, which also keeps traffic inspectable in Burp or mitmproxy
instead of slipping out over UDP/443.

**Disk trail.** Password manager and autofill off, cookies session-only, and
cookies, cache, and site settings cleared on exit.

Browsing history and the bookmarks bar are intentionally left at their defaults.

## Deliberate tradeoffs

Read these before installing on a machine you use for ordinary browsing.

**Safe Browsing is off** (`SafeBrowsingProtectionLevel: 0`). No phishing or
malware interstitials. Safe Browsing works by sending URL hashes to Google, so
turning it off is the point — but it is a genuine loss of protection, and the
wrong default for a daily driver.

**Search defaults to DuckDuckGo**, with no suggest endpoint configured.

**QUIC is disabled.** Slightly slower on some sites; much easier to intercept.

**DNS-over-HTTPS is off**, so Chrome uses the system resolver. On a box where you
control routing that is the predictable choice. On an untrusted network it means
plaintext DNS.

**`CLEAN_OTHER_BROWSERS=1` deletes files.** It removes `99-chrome-lockdown.json`,
`lockdown.json`, and `no-extensions.json` from Brave, Chromium, and Edge policy
directories. If you keep your own policy file at one of those paths under one of
those names, it will be deleted. It is opt-in for exactly this reason. It exists
because earlier versions of this script wrote to those directories by mistake.

## Why the audit exists

Chrome policies are deprecated and removed constantly, and they fail silently —
a dead key shows up in `chrome://policy` as a warning nobody reads, and the
protection you thought you had is simply absent.

This is not hypothetical. The first draft of this policy file contained nine
broken keys, including:

- `PrivacySandboxIpProtectionEnabled` — Linux support ended at Chrome 143
- `SafeBrowsingExtendedReportingEnabled` — no effect since M145; feature removed
- `GeminiSettings` — never supported on Linux at all
- `HistorySearchSettings` — deprecated in M157, feature removed
- `AutofillAddressEnabled` / `AutofillCreditCardEnabled` — deprecated in M156,
  replaced by `AutofillSettings`, which takes a completely different shape
- `FindAndFillWithGeminiSettings` — does not exist

All nine came from policy lists and hardening guides that were correct when
written. That is the failure mode this repo is built to avoid.

### Running the audit yourself

```bash
pip install pyyaml
./audit/fetch-policy-defs.sh 156.0.8078.47 /tmp/defs
python3 -I audit/audit_policies.py \
  /tmp/defs/components/policy/resources/templates/policy_definitions \
  lockdown.json 156
```

It sparse-clones only `components/policy/resources/templates/policy_definitions`
from the Chromium mirror at the given release tag — about 1,500 YAML files, not
the full tree — then checks every key in `lockdown.json` for:

- presence in that release
- `deprecated: true`
- Linux support, and whether the `supported_on` range has an end version
- `cloud_only` (set from a local file, these report an error — this is how
  `GenAiDefaultSettings` was caught)
- valid enum or schema type for the configured value

Exit code is non-zero if anything fails.

### CI

`.github/workflows/policy-audit.yml` runs daily. It asks the Chrome
VersionHistory API for the live Linux version on stable, beta, and dev, then
audits against each one's Chromium tag.

Stable is blocking and files an issue on failure. Beta and dev are advisory, so
upcoming removals show up weeks before they reach you.

> **Scheduled workflows stop after 60 days of repository inactivity.** GitHub
> disables them quietly. On a successful scheduled stable run this workflow
> commits a timestamp to `.audit-stamp`, which counts as activity and keeps the
> schedule alive. Remove the `stamp` job if you would rather not have the commits.

## Not affiliated with Google or Anthropic

Policy semantics come from Chromium's published definitions. Chrome, Chromium,
and Brave are trademarks of their respective owners.

## License

MIT. See [LICENSE](LICENSE).
