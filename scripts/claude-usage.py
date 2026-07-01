#!/usr/bin/env python3
"""
claude-usage.py — Claude Code token usage tracker.
Reads ~/.claude/projects/**/*.jsonl (all projects on this machine).

  python3 claude-usage.py          # today + past 7 days (default)
  python3 claude-usage.py --days N # past N days

Costs are estimated at Anthropic API list rates, not your subscription price.
Prices: https://www.anthropic.com/pricing
"""

import json
import glob
import os
import sys
from collections import defaultdict
from datetime import date, timedelta

# ── Optional: set your monthly token limit to see a progress bar ────────────
# Claude Code doesn't expose this via API — check claude.ai/settings/usage.
MONTHLY_TOKEN_LIMIT = None  # e.g. 50_000_000
# ────────────────────────────────────────────────────────────────────────────

PRICING = {
    "claude-opus-4":   {"input": 15.00, "cache_write": 18.75, "cache_read": 1.50, "output": 75.00},
    "claude-sonnet-4": {"input":  3.00, "cache_write":  3.75, "cache_read": 0.30, "output": 15.00},
    "claude-haiku-4":  {"input":  0.80, "cache_write":  1.00, "cache_read": 0.08, "output":  4.00},
}
_FALLBACK = PRICING["claude-sonnet-4"]


def get_pricing(model):
    if model:
        for prefix, rates in PRICING.items():
            if model.startswith(prefix):
                return rates
    return _FALLBACK


def estimate_cost(model, inp, cw, cr, out):
    r = get_pricing(model)
    def pm(rate, n): return rate * n / 1_000_000
    return pm(r["input"], inp) + pm(r["cache_write"], cw) + pm(r["cache_read"], cr) + pm(r["output"], out)


def load_usage():
    base = os.path.expanduser("~/.claude/projects")
    daily = defaultdict(lambda: {"input": 0, "cache_write": 0, "cache_read": 0,
                                  "output": 0, "cost": 0.0, "turns": 0})
    for filepath in glob.glob(os.path.join(base, "**", "*.jsonl"), recursive=True):
        try:
            with open(filepath, errors="ignore") as fh:
                for raw in fh:
                    try:
                        d = json.loads(raw)
                    except json.JSONDecodeError:
                        continue
                    if d.get("type") != "assistant":
                        continue
                    msg = d.get("message")
                    if not isinstance(msg, dict):
                        continue
                    usage = msg.get("usage")
                    if not usage:
                        continue
                    ts = d.get("timestamp", "")
                    day = ts[:10] if ts else "unknown"
                    model = msg.get("model", "")
                    inp = usage.get("input_tokens", 0)
                    cw  = usage.get("cache_creation_input_tokens", 0)
                    cr  = usage.get("cache_read_input_tokens", 0)
                    out = usage.get("output_tokens", 0)
                    rec = daily[day]
                    rec["input"]       += inp
                    rec["cache_write"] += cw
                    rec["cache_read"]  += cr
                    rec["output"]      += out
                    rec["cost"]        += estimate_cost(model, inp, cw, cr, out)
                    rec["turns"]       += 1
        except OSError:
            continue
    return daily


def total_toks(rec):
    return rec["input"] + rec["cache_write"] + rec["cache_read"] + rec["output"]


def fmt(n):
    if n >= 1_000_000: return f"{n/1_000_000:.1f}M"
    if n >= 1_000:     return f"{n/1_000:.0f}K"
    return str(n)


def bar(val, max_val, width=16):
    if max_val == 0:
        return "░" * width
    filled = round(val / max_val * width)
    return "█" * filled + "░" * (width - filled)


def month_label(d):
    return date.fromisoformat(d).strftime("%B %Y")


def main():
    args = sys.argv[1:]
    n_days = 7
    if "--days" in args:
        idx = args.index("--days")
        try:
            n_days = int(args[idx + 1])
        except (IndexError, ValueError):
            print("Usage: --days N"); sys.exit(1)

    daily = load_usage()
    if not daily:
        print("No usage data found in ~/.claude/projects/")
        return

    today_str  = str(date.today())
    week_dates = [str(date.today() - timedelta(days=i)) for i in range(n_days - 1, -1, -1)]
    month_str  = today_str[:7]
    month_days = [d for d in daily if d.startswith(month_str)]

    today_rec = daily.get(today_str, {"input":0,"cache_write":0,"cache_read":0,"output":0,"cost":0.0,"turns":0})
    month_rec = {k: sum(daily[d][k] for d in month_days if k in daily[d])
                 for k in ("input","cache_write","cache_read","output","cost","turns")}

    # ── scale bar to max output in the window
    week_outputs = [daily[d]["output"] for d in week_dates if d in daily]
    max_out = max(week_outputs) if week_outputs else 1

    W = 54  # total display width

    def rule(char="─"): print(" " + char * (W - 2))

    print()
    print(f" ┌{'─' * (W - 2)}┐")
    title = "Claude Code · Token Usage"
    pad = W - 2 - len(title)
    print(f" │ {title}{' ' * (pad - 1)}│")
    print(f" └{'─' * (W - 2)}┘")
    print()

    # ── Today ──────────────────────────────────────────
    print(f"  Today · {date.today().strftime('%b %d, %Y')}")
    rule("╌")
    print(f"   Output    {fmt(today_rec['output'])} tokens")
    print(f"   Total     {fmt(total_toks(today_rec))} tokens  (context + output)")
    print(f"   Turns     {today_rec['turns']}")
    print(f"   Est. Cost ~${today_rec['cost']:.2f}")
    print()

    # ── Past N days ────────────────────────────────────
    label = "Today" if n_days == 1 else f"Past {n_days} Days"
    print(f"  {label}")
    rule("╌")

    week_total = {"output": 0, "cost": 0.0, "turns": 0, "total": 0}

    for d in week_dates:
        is_today = d == today_str
        marker = " ◀" if is_today else "  "
        try:
            day_label = date.fromisoformat(d).strftime("%b %d")
        except ValueError:
            day_label = d
        if d in daily:
            rec = daily[d]
            out = rec["output"]
            tot = total_toks(rec)
            cost = rec["cost"]
            turns = rec["turns"]
            week_total["output"] += out
            week_total["cost"]   += cost
            week_total["turns"]  += turns
            week_total["total"]  += tot
            b = bar(out, max_out)
            print(f"   {day_label}{marker}  {fmt(out):>6}  {b}  ~${cost:>5.2f}")
        else:
            print(f"   {day_label}    {'—':>6}")

    rule("╌")
    print(f"   {'Total':10}  {fmt(week_total['output']):>6}  {'':16}  ~${week_total['cost']:>5.2f}")
    print()

    # ── This month ─────────────────────────────────────
    print(f"  This Month · {date.today().strftime('%B %Y')}")
    rule("╌")
    month_out   = month_rec["output"]
    month_total = total_toks(month_rec)
    month_cost  = month_rec["cost"]
    print(f"   Output    {fmt(month_out)} tokens")
    print(f"   Total     {fmt(month_total)} tokens")
    print(f"   Turns     {month_rec['turns']}")
    print(f"   Est. Cost ~${month_cost:.2f}")
    if MONTHLY_TOKEN_LIMIT:
        pct = month_total / MONTHLY_TOKEN_LIMIT * 100
        b = bar(month_total, MONTHLY_TOKEN_LIMIT, 20)
        print(f"   Limit     {b}  {pct:.1f}% of {fmt(MONTHLY_TOKEN_LIMIT)}")
    print()

    rule("─")
    print(f"   Output = tokens generated  ·  Total = all context tokens")
    print(f"   Cost estimated at API list rates, not subscription price")
    print()


if __name__ == "__main__":
    main()
