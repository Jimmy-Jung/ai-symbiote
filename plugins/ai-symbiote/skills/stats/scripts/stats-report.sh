#!/usr/bin/env bash
# ai-symbiote stats reporter.
#
# Author: JunyoungJung
# Date: 2026-04-14

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../hooks/scripts/lib/common.sh"

STATE_DIR=""
PLUGIN_ROOT=""
MODE="report"

while [ $# -gt 0 ]; do
  case "$1" in
    --state-dir)
      STATE_DIR="${2:-}"
      shift 2
      ;;
    --plugin-root)
      PLUGIN_ROOT="${2:-}"
      shift 2
      ;;
    --baseline)
      MODE="baseline"
      shift
      ;;
    --reset)
      MODE="reset"
      shift
      ;;
    *)
      echo "Usage: stats-report.sh [--baseline|--reset] [--state-dir PATH] [--plugin-root PATH]" >&2
      exit 1
      ;;
  esac
done

STATE_DIR="${STATE_DIR:-$(ensure_state_dir)}"
PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

mkdir -p "$STATE_DIR/state"

python3 - "$STATE_DIR" "$PLUGIN_ROOT" "$MODE" <<'PY'
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

state_dir = Path(sys.argv[1])
plugin_root = Path(sys.argv[2])
mode = sys.argv[3]
usage_dir = state_dir / "usage-data"
skills_dir = plugin_root / "skills"
baseline_path = state_dir / "state" / "stats-baseline.json"


def now_utc() -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0)


def parse_ts(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)
    except Exception:
        return None


def read_jsonl(path):
    if not path.exists():
        return []
    items = []
    for raw in path.read_text().splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            items.append(json.loads(raw))
        except Exception:
            continue
    return items


def relative_time(ts):
    parsed = parse_ts(ts)
    if not parsed:
        return "never"
    delta = now_utc() - parsed
    if delta.days >= 1:
        return f"{delta.days}d ago"
    hours = delta.seconds // 3600
    if hours >= 1:
        return f"{hours}h ago"
    minutes = delta.seconds // 60
    if minutes >= 1:
        return f"{minutes}m ago"
    return "just now"


def load_counter_dir(path):
    data = {}
    if not path.exists():
        return data
    for item in path.iterdir():
        if not item.is_file():
            continue
        raw = item.read_text().strip()
        count = 0
        last_used = None
        if "|" in raw:
            count_raw, last_used = raw.split("|", 1)
            try:
                count = int(count_raw)
            except Exception:
                count = 0
        else:
            try:
                count = int(raw)
            except Exception:
                count = 0
        data[item.name] = {"count": count, "last_used": last_used}
    return data


def discover_skill_names():
    names = []
    if not skills_dir.exists():
        return names
    for skill_md in sorted(skills_dir.glob("*/SKILL.md")):
        names.append(skill_md.parent.name)
    return names


def read_skill_frontmatter(path):
    lines = path.read_text().splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    data = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip().strip('"')
    return data


def discover_command_names():
    names = []
    if not skills_dir.exists():
        return names
    for skill_md in sorted(skills_dir.glob("*/SKILL.md")):
        meta = read_skill_frontmatter(skill_md)
        if meta.get("user-invocable", "").lower() == "true":
            names.append(skill_md.parent.name)
    return names


def merge_items(names, counters):
    merged = []
    all_names = sorted(set(names) | set(counters.keys()))
    for name in all_names:
        payload = counters.get(name, {"count": 0, "last_used": None})
        merged.append({"name": name, "count": payload["count"], "last_used": payload["last_used"]})
    merged.sort(key=lambda item: (-item["count"], item["name"]))
    return merged


def count_active_rules(context_path):
    if not context_path.exists():
        return 0, 0, 0
    lines = context_path.read_text().splitlines()
    harness_count = sum(1 for line in lines if line.startswith("[Harness #"))
    seed_count = sum(1 for line in lines if line.startswith("[Seed #"))
    return len(lines), harness_count, seed_count


def compute_trend(events):
    current_start = now_utc() - timedelta(days=7)
    previous_start = now_utc() - timedelta(days=14)
    current = 0
    previous = 0
    for item in events:
        ts = parse_ts(item.get("ts"))
        if not ts:
            continue
        if ts >= current_start:
            current += 1
        elif previous_start <= ts < current_start:
            previous += 1
    if current > previous:
        trend = "up"
    elif current < previous:
        trend = "down"
    else:
        trend = "flat"
    return current, previous, trend


def compute_repeat_rate(events):
    buckets = defaultdict(list)
    for item in events:
        ts = parse_ts(item.get("ts"))
        error_type = item.get("error_type")
        file_path = item.get("file") or "(unknown)"
        if not ts or not error_type:
            continue
        buckets[(error_type, file_path)].append(ts)
    total = len(buckets)
    repeated = 0
    for timestamps in buckets.values():
        timestamps.sort()
        if len(timestamps) < 2:
            continue
        for idx in range(1, len(timestamps)):
            if timestamps[idx] - timestamps[idx - 1] <= timedelta(days=7):
                repeated += 1
                break
    rate = (repeated / total * 100.0) if total else 0.0
    return total, repeated, rate


def security_summary(events):
    blocked = sum(1 for item in events if item.get("action") == "blocked")
    warned = sum(1 for item in events if item.get("action") == "warned")
    categories = Counter(item.get("category", "unknown") for item in events)
    risks = Counter(item.get("risk", "warned") for item in events if item.get("risk"))
    recent = []
    for item in sorted(events, key=lambda entry: entry.get("ts", ""))[-3:]:
        detail = item.get("file") or item.get("command") or item.get("rule_id") or "n/a"
        recent.append((item.get("ts", "unknown"), item.get("action", "unknown"), item.get("category", "unknown"), detail))
    return {
        "total": len(events),
        "blocked": blocked,
        "warned": warned,
        "categories": categories,
        "risks": risks,
        "recent": recent,
    }


def print_usage_stats():
    tracked_since = usage_dir.joinpath(".tracked-since").read_text().strip() if usage_dir.joinpath(".tracked-since").exists() else None
    tracked_days = 0
    if tracked_since:
        tracked_at = parse_ts(tracked_since)
        if tracked_at:
            tracked_days = (now_utc() - tracked_at).days
    skill_counters = load_counter_dir(usage_dir / "skills")
    command_counters = load_counter_dir(usage_dir / "commands")
    skills = merge_items(discover_skill_names(), skill_counters)
    commands = merge_items(discover_command_names(), command_counters)

    print(f"[Usage Stats] Tracking period: {tracked_since or 'unknown'} ~ now ({tracked_days} days)")
    print("")
    active_skills = [item for item in skills if item["count"] > 0]
    print(f"Skills ({len(skills)}, {len(active_skills)} active):")
    for idx, item in enumerate(active_skills[:10], start=1):
        print(f"  #{idx}  {item['name']:<16} {item['count']} uses  (last: {relative_time(item['last_used'])})")
    unused_skills = [item for item in skills if item["count"] == 0]
    if unused_skills:
        print("  --- Unused (0 uses) ---")
        for item in unused_skills[:10]:
            print(f"  {item['name']:<18} 0 uses")
    print("")

    active_commands = [item for item in commands if item["count"] > 0]
    print(f"Commands ({len(commands)}, {len(active_commands)} active):")
    for idx, item in enumerate(active_commands[:10], start=1):
        print(f"  #{idx}  {item['name']:<16} {item['count']} uses  (last: {relative_time(item['last_used'])})")
    unused_commands = [item for item in commands if item["count"] == 0]
    if unused_commands:
        print("  --- Unused (0 uses) ---")
        for item in unused_commands[:10]:
            print(f"  {item['name']:<18} 0 uses")


def print_harness_and_security():
    harness_log = read_jsonl(state_dir / "harness-log.jsonl")
    security_log = [item for item in read_jsonl(state_dir / "security-log.jsonl") if item.get("type") == "security"]
    context_lines, harness_rules, seed_rules = count_active_rules(state_dir / "context.md")

    print("")
    print("[Harness Evolution Metrics]")
    print("")
    total_created = sum(1 for item in harness_log if item.get("type") == "rule_created")
    gc_removed = max(total_created - harness_rules, 0)
    print(f"Auto-generated rules:")
    print(f"  Active: {harness_rules}  |  Total created: {total_created}  |  GC removed: {gc_removed}")

    mistake_events = [item for item in harness_log if item.get("error_type")]
    this_week, last_week, trend = compute_trend(mistake_events)
    print("")
    print("Mistake frequency (last 30 days):")
    print(f"  This week: {this_week}  |  Last week: {last_week}  |  Trend: {trend}")

    top_mistakes = Counter((item.get("error_type", "unknown"), item.get("file", "(unknown)")) for item in mistake_events)
    print("")
    print("TOP 5 mistake types:")
    if not top_mistakes:
        print("  - No harness mistake events yet.")
    else:
        for idx, ((error_type, file_path), count) in enumerate(top_mistakes.most_common(5), start=1):
            print(f"  #{idx}  {error_type} @ {file_path}    {count} times")

    total_patterns, repeated_patterns, repeat_rate = compute_repeat_rate(mistake_events)
    print("")
    print("Harness effectiveness:")
    print(f"  Same mistake recurrence after rule creation: {repeated_patterns}/{total_patterns} ({repeat_rate:.1f}%)")

    prevention_events = [item for item in harness_log if item.get("type") == "rule_prevented"]
    prevention_counts = Counter(str(item.get("rule_id", "unknown")) for item in prevention_events)
    all_rule_ids = set()
    context_path = state_dir / "harness-rules.md"
    if context_path.exists():
        for line in context_path.read_text().splitlines():
            if line.startswith("[Harness #") or line.startswith("[Seed #"):
                rule_id = line.split("#", 1)[1].split("]", 1)[0]
                all_rule_ids.add(rule_id)
    zero_prevention = sorted(rule_id for rule_id in all_rule_ids if prevention_counts.get(rule_id, 0) == 0)
    print("")
    print("Rule prevention stats (v2):")
    print(f"  Total preventions: {sum(prevention_counts.values())}")
    if prevention_counts:
        print("  Top 5 most effective rules:")
        for idx, (rule_id, count) in enumerate(prevention_counts.most_common(5), start=1):
            print(f"    #{idx}  [Rule #{rule_id}] prevented: {count} times")
    else:
        print("  Top 5 most effective rules:")
        print("    - No prevention events yet.")
    print(f"  Rules with 0 preventions: {len(zero_prevention)} (gc candidates)")

    guard_blocks = [item for item in harness_log if item.get("error_type") == "guard_blocked"]
    command_patterns = Counter(item.get("command", "(unknown)") for item in guard_blocks)
    print("")
    print("Guard blocked commands (v2):")
    print(f"  Total blocks: {len(guard_blocks)}")
    if command_patterns:
        top_patterns = ", ".join(f"{cmd} x{count}" for cmd, count in command_patterns.most_common(3))
        print(f"  Top patterns: {top_patterns}")
    else:
        print("  Top patterns: none")

    sec = security_summary(security_log)
    print("")
    print("[Security Telemetry]")
    print("")
    print(f"Events: {sec['total']}  |  Blocked: {sec['blocked']}  |  Warned: {sec['warned']}")
    if sec["categories"]:
        category_line = ", ".join(f"{name} x{count}" for name, count in sec["categories"].most_common(5))
        print(f"Top categories: {category_line}")
    else:
        print("Top categories: none")
    if sec["risks"]:
        risk_line = ", ".join(f"{name} x{count}" for name, count in sec["risks"].most_common(5))
        print(f"Risk breakdown: {risk_line}")
    else:
        print("Risk breakdown: warned-only")
    if sec["recent"]:
        print("Recent security events:")
        for ts, action, category, detail in sec["recent"]:
            print(f"  - {ts} | {action} | {category} | {detail}")
    else:
        print("Recent security events:")
        print("  - No security events yet.")

    print("")
    print(f"context.md: {context_lines} lines ({harness_rules} harness rules + {seed_rules} seed rules)")
    harness_lines = len((state_dir / "harness-log.jsonl").read_text().splitlines()) if (state_dir / "harness-log.jsonl").exists() else 0
    security_lines = len((state_dir / "security-log.jsonl").read_text().splitlines()) if (state_dir / "security-log.jsonl").exists() else 0
    print(f"harness-log.jsonl: {harness_lines} lines")
    print(f"security-log.jsonl: {security_lines} lines")


def print_session_metrics():
    sessions_file = usage_dir / "sessions.jsonl"
    print("")
    print("[Session Metrics]")
    print("")
    if not sessions_file.exists():
        print("No session data recorded yet.")
        return
    sessions = read_jsonl(sessions_file)
    total = len(sessions)
    cutoff_7d = now_utc() - timedelta(days=7)
    cutoff_24h = now_utc() - timedelta(hours=24)
    last_7d = sum(1 for s in sessions if parse_ts(s.get("ts")) and parse_ts(s.get("ts")) >= cutoff_7d)
    last_24h = sum(1 for s in sessions if parse_ts(s.get("ts")) and parse_ts(s.get("ts")) >= cutoff_24h)
    print(f"Recent sessions (max 100): {total}")
    print(f"Sessions in last 7 days: {last_7d}")
    print(f"Sessions in last 24 hours: {last_24h}")


def run_baseline():
    harness_log = read_jsonl(state_dir / "harness-log.jsonl")
    mistake_events = [item for item in harness_log if item.get("error_type")]
    total_patterns, repeated_patterns, repeat_rate = compute_repeat_rate(mistake_events)
    measured_at = now_utc().isoformat().replace("+00:00", "Z")
    payload = {
        "measuredAt": measured_at,
        "totalPatterns": total_patterns,
        "repeatedPatterns": repeated_patterns,
        "repeatRate": round(repeat_rate, 2),
    }
    baseline_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
    print(f"[Harness Baseline] Measured on {measured_at}")
    print("")
    print("Repeat rate (same {error_type, file} within 7 days):")
    print(f"  Total unique error patterns: {total_patterns}")
    print(f"  Patterns that recurred: {repeated_patterns}")
    print(f"  Repeat rate: {repeat_rate:.1f}%")
    print(f"Saved: {baseline_path}")


def run_reset():
    removed = 0
    for target in [usage_dir / "skills", usage_dir / "commands"]:
        if not target.exists():
            continue
        for item in target.iterdir():
            if item.is_file():
                item.unlink()
                removed += 1
    tracked_since = usage_dir / ".tracked-since"
    if tracked_since.exists():
        tracked_since.unlink()
        removed += 1
    if baseline_path.exists():
        baseline_path.unlink()
        removed += 1
    print("[Usage Stats] Tracking data reset complete.")
    print(f"Removed files: {removed}")


if mode == "baseline":
    run_baseline()
elif mode == "reset":
    run_reset()
else:
    print_usage_stats()
    print_harness_and_security()
    print_session_metrics()
PY
