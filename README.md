# Claude Account Switcher

Run two Claude Pro accounts side by side on one Windows machine -- same skills,
same `CLAUDE.md`, same plugins, independent logins -- switch between them in
the *same terminal window* mid-conversation, and see both accounts' rate-limit
usage at a glance. No `/logout`, no re-typing your login, no third-party app
holding your credentials.

Built while setting up a two-account workflow (a personal Claude Pro account
and a work one) so that either account could pick up any open conversation
with full feature parity -- not to get around usage limits, which is a
separate question you should check against [Anthropic's own terms](https://www.anthropic.com/legal)
before relying on this for that purpose. This project is about identity
separation and portability: work stays on the work account, personal stays
personal, and neither login is worse-equipped than the other.

Everything here is Windows + PowerShell 5.1 specific (that's what I run), and
pins some undocumented Claude Code CLI internals to version **2.1.282** --
see [Fragile bits](#fragile-bits-read-before-you-rely-on-this) before you
build anything serious on top of it.

## Why not just `/logout` / `/login`?

That works, but it's the only option Claude Code ships, and it means:
- every switch costs a login flow
- the account you're *not* using stays logged out, so there's no "just check
  the other one's quota real quick"
- if you're mid-conversation and hit a rate limit, you lose your place

## The actual mechanism: `CLAUDE_CONFIG_DIR`

Claude Code reads `CLAUDE_CONFIG_DIR` to decide where its config, credentials,
skills, and session history live -- default is `~/.claude`. Point two
different folders at it and you get two fully independent Claude Code
installs that can run at the same time:

```
claude-sandbox/
  acc1/.claude/     <- account 1's own credentials + settings
  acc2/.claude/     <- account 2's own credentials + settings
  shared/           <- skills, CLAUDE.md, settings.json -- edit once, both accounts see it
    projects/       <- junctioned into both acc1 and acc2, so conversations are resumable from either account
```

`shared/skills`, `shared/CLAUDE.md`, and `shared/settings.json` are
[NTFS junctions](https://learn.microsoft.com/windows-server/administration/windows-commands/mklink)
or hardlinks into each account's `.claude` folder, so both accounts see
identical capabilities. `shared/projects` is junctioned the same way, which is
what makes "resume this conversation under the *other* account" possible --
`--resume <id>` / `--continue` just reads whichever transcript file matches,
regardless of which account's credentials wrote it.

**What's deliberately *not* shared:** `USERPROFILE`/`HOME` are never touched.
Only `CLAUDE_CONFIG_DIR` changes. Git identity, SSH keys, `.npmrc`, `gh` auth
-- all keep working exactly as they do outside the sandbox, because nothing
about "which user you are to Windows" ever changes.

## Setting it up (manual -- there's no installer)

This repo ships the *scripts*, not a one-command installer (see
[Fragile bits](#fragile-bits-read-before-you-rely-on-this) for why I didn't
build one). Rough steps, adjust paths to taste:

1. Pick a root, e.g. `C:\Users\you\claude-sandbox`. Copy everything in
   [`scripts/`](scripts/) there.
2. Create `acc1/.claude/` and `acc2/.claude/` (empty is fine).
3. Copy your real `~/.claude/skills/`, `~/.claude/CLAUDE.md`, and a
   **sanitized** `~/.claude/settings.json` (drop `hooks`, any router/proxy
   config, `enabledPlugins` -- those get re-added per account as you install
   plugins) into `shared/`.
4. From an elevated-enough shell (junctions don't need admin on modern
   Windows, but test this): `mklink /J acc1\.claude\skills shared\skills`,
   same for `acc2`, same pattern for `CLAUDE.md` (use `mklink /H` for files)
   and `projects`.
5. Open a terminal, run `claude` under `CLAUDE_CONFIG_DIR=...\acc1\.claude`,
   log in to account 1. Repeat for `acc2` with the other account.
6. Copy [`scripts/profile-snippet.example.ps1`](scripts/profile-snippet.example.ps1)
   into your `$PROFILE`, replacing `<SANDBOX_ROOT>`.
7. Copy the two `.cmd` templates from `scripts/bin/` (drop `.template`,
   replace `<SANDBOX_ROOT>`) if you also want a tool like
   [Orca](https://github.com/stablyai/orca) to launch these directly.

Open a new terminal. `claude1` / `claude2` should both work, independently,
at the same time.

## What each script does

| Script | Does |
|---|---|
| `launch.ps1` | The core. Runs Claude under one account in the current window; on `/exit`, offers a one-key switch to the other account that resumes the exact same conversation. See [Mid-conversation account switching](#mid-conversation-account-switching-without-exiting-the-window) below. |
| `sw.ps1` | Manual switch for a window you already exited without using the built-in prompt. |
| `pane-state.ps1` | Shared helper: gives every terminal *window* (not folder) a stable identity, so `launch.ps1`/`sw.ps1` always resume the conversation *this* window had, never a guess. |
| `cont.ps1` | Pick up a session that was running under your normal (non-sandboxed) `~/.claude` account -- e.g. to migrate already-open work into the sandbox. |
| `handoff-save.ps1` | Snapshots every currently-live session (across the real account and both sandbox accounts) to a file, for `cont.ps1` to read later. |
| `usage.ps1` | Prints both accounts' 5-hour and 7-day rate-limit usage side by side. |
| `sync-settings.ps1` | One-way, non-destructive merge of `shared/settings.json` into both accounts -- keeps account-only keys (like installed plugins) intact. Dry-run by default. |
| `shared/statusline.sh` | A modified copy of Claude Code's own default statusline script -- same visual output, plus one small addition that makes `usage.ps1` possible (below). |

## Mid-conversation account switching (without exiting the window)

**Be precise about what this is:** Claude Code has no API to change the
logged-in account of a running process. The only way to do that mid-process
is to overwrite the credentials file underneath it while it's running --
which is what a multi-account tool doing "hot-swap" is actually doing, race
conditions and all (see the [Orca](#evaluating-a-gui-orca) section).
I deliberately didn't build that.

What `launch.ps1` actually does: you still type `/exit`. But the *window*
doesn't close -- it's running a loop, not a one-shot launch -- and the moment
Claude exits, it asks right there:

```
[acc1] exited (session a1b2c3d4). Press 's' + Enter to switch to acc2 and continue, or just Enter to stop
```

Press `s`, and it relaunches Claude under the other account with
`--resume <that exact session id>`. Same window, same conversation, one
keystroke. That's the realistic ceiling for "switch accounts without leaving
the window" as long as Claude Code's own session model stays what it is
today.

### Bug: `--continue` picked the wrong session

The first version of this used `--continue` ("resume whatever's newest in
this folder") for the switch. That's wrong the moment two sessions are open
in the *same* folder at once -- e.g. two terminal panes both working in the
same large repo, one per account, both being typed into around the same
time. `--continue` in the second pane could resume the *first* pane's
conversation instead of its own, with both processes then appending to the
same transcript file.

Fixed by tracking the **exact session id** the current window's own process
got, via Claude Code's live-session registry file,
`<CLAUDE_CONFIG_DIR>\sessions\<pid>.json` (undocumented, observed on
2.1.282 -- see [Fragile bits](#fragile-bits-read-before-you-rely-on-this)).
Every switch after that uses `--resume <that id>` explicitly. Folder-based
guessing is gone entirely.

### Bug: `Start-Process -ArgumentList $null` throws

`@($Rest)` in PowerShell, when `$Rest` (the passed-through extra args) is
actually `$null` (i.e. you ran `claude1` with no extra arguments), produces a
**one-element array containing `$null`** -- not an empty array. Passing that
to `Start-Process -ArgumentList` throws a parameter-validation error before
Claude even starts. Fixed by filtering nulls out, and by omitting
`-ArgumentList` entirely (via splatting) when there's nothing to pass.

### Bug: `Start-Process -FilePath 'claude'` -> "%1 is not a valid Win32 application"

The npm-installed `claude` command actually resolves to *three* different
files on PATH (`claude`, `claude.cmd`, `claude.ps1`), plus a real binary two
levels deeper (`node_modules\@anthropic-ai\claude-code\bin\claude.exe`).
PowerShell's own `&` operator picks a working one transparently. `Start-Process
-FilePath 'claude'`, which resolves names differently (closer to
`ShellExecute`), landed on a file that isn't directly runnable, and Windows
gave the classic not-a-valid-Win32-application error.

Fixed by resolving the real `.exe` explicitly at runtime (same relative path
`claude.cmd` itself uses), so `Start-Process` gets an actual executable --
and, as a side effect, so the pid it returns is the *same* pid Claude Code's
own session registry uses, which the switching logic above depends on.

## Usage dashboard, without touching your token

`usage.ps1` shows both accounts' quota:

```
Claude usage -- both sandbox accounts (from statusline piggyback, not a live API call)
acc1   5h: 12% in 3h 40m (18:20)         7d: 41% in 5d 2h (Oct 1, 09:00)
acc2   5h: 64% in 1h 0m (18:20)          7d: 8% in 2d 4h (Sep 28, 22:00)
```

Claude Code already pipes a `rate_limits` object to whatever `statusLine`
command you've configured, on every turn -- that's a real, intentional
feature, not something I reverse-engineered. `shared/statusline.sh` is a
one-line addition on top of Claude Code's own generated default script: after
it parses that JSON (which it was already doing, to draw the visible status
line), it also writes the numbers to `state/usage-<account>.json`, keyed by
`$CLAUDE_CONFIG_DIR` so each account's file only gets touched by that
account's own sessions. No extra network call, no reading `.credentials.json`,
no token ever touches this script.

The tradeoff: a number is only as fresh as that account's last turn. Haven't
used an account in a while and its numbers look stale? `usage.ps1` flags that
explicitly (`[stale, 34m old]`) instead of pretending it's live.

### Bug: `~` in `statusLine.command` silently pointed at the real script

The default is `bash ~/.claude/statusline.sh`. Since `HOME` is deliberately
never overridden in this setup, `~` always resolves to the *real* home
directory -- editing the sandboxed copy did precisely nothing, for a while,
before I noticed the numbers never showed up. Fixed by pointing each
account's `statusLine.command` at an absolute path to the shared script
instead of a `~`-relative one.

## Other bugs found along the way

- **Opening Claude from the Windows home directory leaked real config in.**
  `C:\Users\<you>\.claude` is a real folder too -- launching Claude *from*
  `C:\Users\<you>` (rather than a project folder) makes Claude Code treat it
  as a project-level config directory and load hooks from your **real**
  account's `settings.json` on top of the sandboxed one, since project-level
  config always applies regardless of `CLAUDE_CONFIG_DIR`. One of those real
  hooks quietly wrote files outside the sandbox. Fix: never launch from the
  home directory; always `cd` into an actual project folder first.
- **PowerShell 5.1 mangled non-ASCII text on write-then-read round trips.**
  `Get-Content`/`Set-Content` without an explicit `-Encoding` default to the
  system codepage, not UTF-8, so anything with Thai text or an em dash that
  got written and then read back (e.g. while merging JSON settings) turned
  into mojibake -- which then broke a hook that tried to parse the corrupted
  JSON. Fixed by using `[IO.File]::ReadAllText`/`WriteAllText` with an
  explicit `UTF8Encoding` everywhere, and by keeping every `.ps1` in this
  repo ASCII-only in the first place so the failure mode can't recur even if
  a reader's PowerShell defaults are equally unhelpful.

## Evaluating a GUI: Orca

Before writing custom tooling I looked at two GUIs that advertise multi-
account Claude support:

- **AgentsRoom** -- advertises the exact feature ("multiple Claude Code
  accounts") but the client itself isn't open source (only a bundled agent
  library is, under a different license). Skipped: no way to check how it
  handles two sets of OAuth credentials.
- **[Orca](https://github.com/stablyai/orca)** (MIT, Stably AI) -- open
  source, so I could actually read the account-switching code before
  installing it. Findings, pinned to commit `e0144a9e` (2026-09-24), Windows
  build:
  - Its "managed account" switch overwrites the **real**
    `~/.claude/.credentials.json` with the target account's credentials, with
    a snapshot-and-restore mechanism and explicit race-condition handling in
    its own source for the case where a live Claude process refreshes tokens
    mid-switch.
  - I tested this by backing up the real credentials file, switching Orca to
    a second account, and switching back: the file byte-for-byte matched the
    backup afterward. I did **not** independently verify that the file
    contained the second account's token while switched -- only that the
    round trip was clean. Take the "it round-trips safely" claim at that
    precision, not further.
  - Decision: didn't use this mechanism for anything beyond that one test.
    The credentials file it's overwriting is shared with every other Claude
    process on the machine, including any real, non-sandboxed session -- an
    unrelated terminal window can be signed out from under you mid-switch.
    `CLAUDE_CONFIG_DIR`-per-account (this repo) never touches that shared
    file at all, so there's nothing to race.
  - Orca still earns a place in the workflow as a terminal/pane manager --
    `claude1`/`claude2` work fine typed into any of its panes, and its
    per-agent "Command" override (Settings -> Agents -> your agent -> Command)
    can point straight at this repo's `bin\claude1.cmd`/`claude2.cmd`, so its
    dedicated Claude button gets the same account and the same switch prompt.
  - Also worth knowing before installing anything: Orca's onboarding writes
    process-status hooks into your **real** `~/.claude/settings.json` (a
    Windows Settings -> Agents -> "Agent status hooks" toggle removes them
    again), and it ships anonymous telemetry that's off by default via
    `ORCA_TELEMETRY_DISABLED=1` / `DO_NOT_TRACK=1` or its own Settings toggle.

## Fragile bits (read before you rely on this)

Everything below is either Windows-specific, version-pinned to Claude Code
`2.1.282`, or genuinely undocumented behavior I only confirmed by inspecting
a live process -- not a stable interface Anthropic has committed to.

- `<CLAUDE_CONFIG_DIR>\sessions\<pid>.json` (the live-session registry
  `launch.ps1` polls) is not a documented API.
- The `rate_limits` field piped to `statusLine` is a real, intentional
  Claude Code feature, but its exact JSON shape isn't a documented contract
  either.
- The path from `claude.cmd` to the real `claude.exe`
  (`node_modules\@anthropic-ai\claude-code\bin\claude.exe`) is this npm
  package's current internal layout, not guaranteed across versions.
- Untested on macOS/Linux. The `CLAUDE_CONFIG_DIR` mechanism itself is
  cross-platform; the PowerShell scripts, the `.cmd` wrappers, and the
  Windows-specific bugs above are not.
- No installer, on purpose -- see the setup section. A script that edits your
  `$PROFILE` and touches `~/.claude` deserves to be read before it's run, not
  downloaded and executed blind. Read [`scripts/`](scripts/) before copying
  anything into a machine you care about.

If a Claude Code update changes any of the above, the affected script will
most likely just silently stop detecting a session id or a usage number --
it fails closed (falls back to "nothing to resume" / "no data yet"), not by
corrupting a conversation.

## Summary in Thai (สรุปภาษาไทย)

โปรเจกต์นี้เกิดจากการอยากใช้ Claude Pro สองบัญชี (งาน + ส่วนตัว) พร้อมกัน โดยให้
ทั้งสองบัญชีมีความสามารถเท่ากันทุกอย่าง (skills, CLAUDE.md, plugin) สลับกันทำงาน
แทนกันได้ และสลับบัญชีในหน้าต่าง terminal เดิมได้โดยไม่ต้อง `/logout` ทุกครั้ง
กลไกหลักคือตัวแปร `CLAUDE_CONFIG_DIR` ของ Claude Code เอง ทำให้แต่ละบัญชีมี
โฟลเดอร์ config แยกกันแต่แชร์ skills/CLAUDE.md/session ผ่าน NTFS junction ได้

จุดที่อยากเน้นสำหรับคนที่จะใช้ต่อ: นี่ไม่ใช่เครื่องมือสำหรับ "หลบ rate limit"
ของ Anthropic ควรอ่านเงื่อนไขการใช้งานของ Anthropic เองก่อนตัดสินใจว่าจะใช้กับ
สองบัญชีในลักษณะไหน จุดประสงค์จริงของโปรเจกต์นี้คือแยก identity งาน/ส่วนตัว และ
ทำให้ทั้งสองบัญชี "ไม่มีใครด้อยกว่ากัน" ในแง่ความสามารถ

ระหว่างทางเจอบั๊กจริงหลายตัวที่คุ้มค่าเก็บไว้เป็นบทเรียน (ไฟล์ config โฮมไดเรกทอรี
รั่วเข้ามาปนกับ sandbox, PowerShell 5.1 ทำอักขระ UTF-8 เพี้ยนตอนอ่าน-เขียนไฟล์,
`--continue` เดา session ผิดตัวตอนมีหลาย session ในโฟลเดอร์เดียว, `Start-Process`
เรียกไฟล์ผิดตัวจนพัง) รายละเอียดและวิธีแก้อยู่ในหัวข้อภาษาอังกฤษด้านบนทั้งหมด
