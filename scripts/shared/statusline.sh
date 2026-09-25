#!/usr/bin/env bash
# Claude Code statusLine script
# Line 1: model | cwd | git branch (dirty/clean)
# Line 2: context usage bar (color-coded) | session cost | session duration
# Line 3: rate limits (5-hour rolling window, 7-day window)
#
# This is a modified copy of Claude Code's own generated default statusline.sh.
# The only addition is the "persist rate limits" block below -- everything else
# (colors, layout, git branch, context bar) is the stock script unchanged.
#
# To customize colors: edit the ANSI codes below (C_* variables).
# To customize fields: edit the printf lines near the bottom.
#
# Uses `node` (not jq) to parse the JSON stdin payload, since jq is not
# guaranteed to be installed but node ships with Claude Code itself.

input=$(cat)

# ---- colors ----
C_RESET='\033[0m'
C_DIM='\033[2m'
C_MODEL='\033[1;36m'      # bold cyan
C_CWD='\033[2;37m'        # dim white
C_BRANCH='\033[33m'       # yellow
C_CLEAN='\033[32m'        # green
C_DIRTY='\033[31m'        # red
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_RED='\033[31m'
C_COST='\033[35m'         # magenta
C_TIME='\033[34m'         # blue

# ---- parse JSON once via node, emit tab-separated fields ----
fields=$(printf '%s' "$input" | node -e '
let data = "";
process.stdin.on("data", c => data += c);
process.stdin.on("end", () => {
  let j = {};
  try { j = JSON.parse(data); } catch (e) {}
  const model = (j.model && j.model.display_name) || "Claude";
  const cwd = (j.workspace && j.workspace.current_dir) || j.cwd || "";
  const ctxPct = (j.context_window && j.context_window.used_percentage);
  const cost = (j.cost && j.cost.total_cost_usd);
  const durMs = (j.cost && j.cost.total_duration_ms);
  const fiveHourPct = (j.rate_limits && j.rate_limits.five_hour && j.rate_limits.five_hour.used_percentage);
  const sevenDayPct = (j.rate_limits && j.rate_limits.seven_day && j.rate_limits.seven_day.used_percentage);
  const fiveHourResetsAt = (j.rate_limits && j.rate_limits.five_hour && j.rate_limits.five_hour.resets_at);
  const sevenDayResetsAt = (j.rate_limits && j.rate_limits.seven_day && j.rate_limits.seven_day.resets_at);
  const nn = (v) => (v === undefined || v === null) ? "" : v;

  // Format a unix-epoch-seconds reset time as "in Xh Ym (HH:MM)" for
  // near-term resets, or "in Xd (Mon DD, HH:MM)" once it is a day or more out.
  const fmtReset = (epochSec) => {
    if (epochSec === undefined || epochSec === null) return "";
    const now = Date.now();
    const resetMs = epochSec * 1000;
    let diffMin = Math.round((resetMs - now) / 60000);
    if (diffMin < 0) diffMin = 0;
    const days = Math.floor(diffMin / 1440);
    const hours = Math.floor((diffMin % 1440) / 60);
    const mins = diffMin % 60;
    const d = new Date(resetMs);
    const clock = d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hour12: false });
    if (days > 0) {
      const dateStr = d.toLocaleDateString([], { month: "short", day: "numeric" });
      return `in ${days}d ${hours}h (${dateStr} ${clock})`;
    } else if (hours > 0) {
      return `in ${hours}h ${mins}m (${clock})`;
    } else {
      return `in ${mins}m (${clock})`;
    }
  };

  const out = [model, cwd, nn(ctxPct), nn(cost), nn(durMs), nn(fiveHourPct), nn(sevenDayPct),
    fmtReset(fiveHourResetsAt), fmtReset(sevenDayResetsAt)];

  // Also persist rate limits for the multi-account usage dashboard (usage.ps1).
  // Piggybacks on data Claude Code already computes for this statusline tick -- no extra
  // API call, no token handling. Only fires when CLAUDE_CONFIG_DIR is set (i.e. an acc1/acc2
  // sandbox launch); a plain, unmodified ~/.claude session never writes this file.
  try {
    const cfgDir = process.env.CLAUDE_CONFIG_DIR;
    if (cfgDir && (fiveHourPct !== undefined || sevenDayPct !== undefined)) {
      const path = require("path");
      const fs = require("fs");
      const accDir = path.dirname(cfgDir.replace(/\\/g, "/"));
      const accName = path.basename(accDir);
      const sandboxRoot = path.dirname(accDir);
      const stateDir = path.join(sandboxRoot, "state");
      fs.mkdirSync(stateDir, { recursive: true });
      const rec = {
        account: accName,
        fiveHourPct: fiveHourPct === undefined ? null : Number(fiveHourPct),
        fiveHourReset: fmtReset(fiveHourResetsAt) || null,
        sevenDayPct: sevenDayPct === undefined ? null : Number(sevenDayPct),
        sevenDayReset: fmtReset(sevenDayResetsAt) || null,
        updatedAt: new Date().toISOString()
      };
      fs.writeFileSync(path.join(stateDir, `usage-${accName}.json`), JSON.stringify(rec));
    }
  } catch (e) {}

  process.stdout.write(out.join("\t"));
});
')

IFS=$'\t' read -r model cwd ctx_pct cost dur_ms five_hour_pct seven_day_pct five_hour_reset seven_day_reset <<< "$fields"
[ -z "$model" ] && model="Claude"
# Show the full cwd path (Windows-style backslashes) instead of just the basename.
cwd_disp="${cwd//\//\\}"
[ -z "$cwd_disp" ] && cwd_disp="$cwd"

# ---- line 1: model | cwd | git branch ----
git_str=""
if [ -n "$cwd" ]; then
    branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
        if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
            git_str=$(printf "🌿 ${C_BRANCH}%s${C_RESET} ${C_DIRTY}✗${C_RESET}" "$branch")
        else
            git_str=$(printf "🌿 ${C_BRANCH}%s${C_RESET} ${C_CLEAN}✓${C_RESET}" "$branch")
        fi
    fi
fi

line1=$(printf "🤖 ${C_MODEL}%s${C_RESET} ${C_DIM}›${C_RESET} 📁 ${C_CWD}%s${C_RESET}" "$model" "$cwd_disp")
if [ -n "$git_str" ]; then
    line1=$(printf "%s ${C_DIM}›${C_RESET} %s" "$line1" "$git_str")
fi

# ---- line 2: context bar | cost | duration ----
if [ -n "$ctx_pct" ]; then
    pct_int=$(printf '%.0f' "$ctx_pct")
    if [ "$pct_int" -ge 80 ]; then bar_color="$C_RED"
    elif [ "$pct_int" -ge 50 ]; then bar_color="$C_YELLOW"
    else bar_color="$C_GREEN"
    fi
    ctx_bar=$(echo "$pct_int" | awk -v col="$bar_color" '{
        n=int($1/100*20+0.5); if(n>20)n=20; if(n<0)n=0;
        fill=""; empty="";
        for(i=0;i<20;i++){ if(i<n) fill=fill"█"; else empty=empty"░" }
        printf "%s%s\033[2m%s\033[0m", col, fill, empty
    }')
    ctx_str=$(printf "%s ${C_RESET}%d%%" "$ctx_bar" "$pct_int")
else
    ctx_str=$(printf "${C_DIM}░░░░░░░░░░░░░░░░░░░░${C_RESET} n/a")
fi

if [ -n "$cost" ]; then
    cost_str=$(printf "💰 ${C_COST}\$%.2f${C_RESET}" "$cost")
else
    cost_str=""
fi

if [ -n "$dur_ms" ]; then
    dur_s=$(( ${dur_ms%.*} / 1000 ))
    dur_h=$(( dur_s / 3600 ))
    dur_m=$(( (dur_s % 3600) / 60 ))
    dur_s2=$(( dur_s % 60 ))
    if [ "$dur_h" -gt 0 ]; then
        dur_str=$(printf "⏱ ${C_TIME}%dh %dm${C_RESET}" "$dur_h" "$dur_m")
    elif [ "$dur_m" -gt 0 ]; then
        dur_str=$(printf "⏱ ${C_TIME}%dm %ds${C_RESET}" "$dur_m" "$dur_s2")
    else
        dur_str=$(printf "⏱ ${C_TIME}%ds${C_RESET}" "$dur_s2")
    fi
else
    dur_str=""
fi

line2=$(printf "⚡ ${C_DIM}ctx${C_RESET} %s" "$ctx_str")
[ -n "$cost_str" ] && line2=$(printf "%s ${C_DIM}·${C_RESET} %s" "$line2" "$cost_str")
[ -n "$dur_str" ] && line2=$(printf "%s ${C_DIM}·${C_RESET} %s" "$line2" "$dur_str")

# ---- line 3: rate limits (5-hour rolling window, 7-day window) ----
rate_pct_color() {
    local pct_int=$1
    if [ "$pct_int" -ge 80 ]; then echo "$C_RED"
    elif [ "$pct_int" -ge 50 ]; then echo "$C_YELLOW"
    else echo "$C_GREEN"
    fi
}

five_hour_str=""
if [ -n "$five_hour_pct" ]; then
    fh_int=$(printf '%.0f' "$five_hour_pct")
    fh_color=$(rate_pct_color "$fh_int")
    five_hour_str=$(printf "🕐 ${C_DIM}5h${C_RESET} ${fh_color}%d%%${C_RESET}" "$fh_int")
    [ -n "$five_hour_reset" ] && five_hour_str=$(printf "%s ${C_DIM}%s${C_RESET}" "$five_hour_str" "$five_hour_reset")
fi

seven_day_str=""
if [ -n "$seven_day_pct" ]; then
    sd_int=$(printf '%.0f' "$seven_day_pct")
    sd_color=$(rate_pct_color "$sd_int")
    seven_day_str=$(printf "📅 ${C_DIM}7d${C_RESET} ${sd_color}%d%%${C_RESET}" "$sd_int")
    [ -n "$seven_day_reset" ] && seven_day_str=$(printf "%s ${C_DIM}%s${C_RESET}" "$seven_day_str" "$seven_day_reset")
fi

line3=""
if [ -n "$five_hour_str" ] || [ -n "$seven_day_str" ]; then
    line3="$five_hour_str"
    if [ -n "$seven_day_str" ]; then
        if [ -n "$line3" ]; then
            line3=$(printf "%s ${C_DIM}·${C_RESET} %s" "$line3" "$seven_day_str")
        else
            line3="$seven_day_str"
        fi
    fi
fi

if [ -n "$line3" ]; then
    printf "%s\n%s\n%s" "$line1" "$line2" "$line3"
else
    printf "%s\n%s" "$line1" "$line2"
fi
