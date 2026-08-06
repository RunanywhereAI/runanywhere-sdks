#!/usr/bin/env python3
"""Regenerates docs/API_CHANGES_2026_08.md mechanically from the API
realignment review's own source-of-truth JSON files. Not hand-written --
re-run this script if any source JSON changes rather than hand-editing
the generated doc.

Usage: python3 gen_api_changes_audit.py <scratch_dir> > docs/API_CHANGES_2026_08.md

<scratch_dir> must contain (produced by the review process, not committed
to this repo -- they're the working data of the review itself, not its
output):
  proposals.json     -- the 243 reviewed proposals + the skeptic's challenges
  seed.json          -- the seeded approve/decline/anti decision per proposal
  care/*.care.json   -- grounded care plans for approve-with-care items
  edits/*.edits.json -- what was actually applied, file:line assertions
"""
import json
import glob
import os
import sys

SCRATCH = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
REPO_COMMIT = "07907b273"
REPO_URL = "https://github.com/RunanywhereAI/runanywhere-sdks"

proposals_raw = json.load(open(f"{SCRATCH}/proposals.json"))
proposals = {p["id"]: p for p in proposals_raw["proposals"]}
challenges = {c["id"]: c for c in proposals_raw["challenges"]}
seed = json.load(open(f"{SCRATCH}/seed.json"))["seed"]

care_by_id = {}
for path in glob.glob(f"{SCRATCH}/care/*.care.json"):
    d = json.load(open(path))
    for plan in d.get("plans", []):
        care_by_id[plan["id"]] = plan

edits_by_id = {}
edits_domain_of = {}
for path in glob.glob(f"{SCRATCH}/edits/*.edits.json"):
    d = json.load(open(path))
    domain = d.get("domain", os.path.basename(path).replace(".edits.json", ""))
    for e in d.get("applied", []):
        edits_by_id[e["id"]] = e
        edits_domain_of[e["id"]] = domain


def seed_key_to_id(key):
    # keys are "<domain>--<id>"
    return key.split("--", 1)[1]


def permalink(file, line=None):
    url = f"{REPO_URL}/blob/{REPO_COMMIT}/idl/{file}"
    if line:
        url += f"#L{line}"
    return url


def truncate(s, n=200):
    s = str(s or "")
    return s if len(s) <= n else s[: n - 1] + "…"


rows_by_domain = {}
decline_rows = []
anti_rows = []

for key, decision in seed.items():
    pid = seed_key_to_id(key)
    p = proposals.get(pid)
    if p is None:
        continue
    domain = p.get("domain", "unknown")
    challenge = challenges.get(pid)

    if decision["act"] == "decline":
        decline_rows.append((domain, pid, p, challenge))
        continue

    if decision["anti"]:
        anti_rows.append((domain, pid, p, challenge))
        continue

    care = care_by_id.get(pid)
    edit = edits_by_id.get(pid)
    rows_by_domain.setdefault(domain, []).append((pid, p, challenge, care, edit))


def render_edit_section(pid, p, challenge, care, edit):
    lines = []
    title = p.get("title", pid)
    lines.append(f"### `{pid}` — {title}\n")

    coords = p.get("protoCoords") or []
    if coords:
        loc_bits = []
        for c in coords[:4]:
            f = c.get("file", "")
            ln = c.get("citedLine")
            label = f
            if c.get("message"):
                label += f" ({c['message']})"
            loc_bits.append(f"[{label}]({permalink(f, ln)})")
        lines.append(f"**Proto location:** {', '.join(loc_bits)}\n")

    lines.append(f"**Why:** {p.get('why', '').strip()}\n")

    verdict = challenge["verdict"] if challenge else "no-verdict"
    lines.append(f"**Skeptic verdict:** `{verdict}`" + (
        f" — {challenge.get('problem', '').strip()}" if challenge and challenge.get("problem") else ""
    ) + "\n")

    if edit:
        lines.append(f"**What changed:** {edit.get('whatIChanged', '').strip()}\n")
        files = edit.get("filesTouched") or []
        if files:
            lines.append(f"**Files touched:** {', '.join('`' + f + '`' for f in files)}\n")
        lines.append(f"**Status:** `{edit.get('status', 'unknown')}`\n")
    else:
        lines.append("**What changed:** _not yet recorded in an edits.json file — flagged for audit._\n")

    if care:
        level = care.get("careLevel", "routine")
        lines.append(f"**Care level:** `{level}`" + (
            " (breaking for existing app callers)" if care.get("breakingForApps") else ""
        ) + "\n")
        if care.get("whatCouldBreak"):
            lines.append(f"**What could break:** {truncate(care['whatCouldBreak'], 600)}\n")
        if care.get("wireSafety"):
            lines.append(f"**Wire safety:** {truncate(care['wireSafety'], 400)}\n")
        if care.get("doFirst"):
            do_first = care["doFirst"]
            if isinstance(do_first, list):
                lines.append("**Do first:**")
                for step in do_first:
                    lines.append(f"  1. {step}")
                lines.append("")

    lines.append("")
    return "\n".join(lines)


out = []
out.append("# API Realignment 2026-08: change log\n")
out.append(
    "Mechanically generated from the review's own source-of-truth JSON "
    f"(`proposals.json`, `seed.json`, care plans, edit records) against "
    f"commit [`{REPO_COMMIT}`]({REPO_URL}/commit/{REPO_COMMIT}) "
    "(`idl: apply 194 approved API simplification decisions across 37 proto files`). "
    "Do not hand-edit this file — regenerate it from `gen_api_changes_audit.py` if the "
    "source data changes.\n"
)
out.append("## Summary\n")
total_approved = sum(len(v) for v in rows_by_domain.values())
out.append(f"| Bucket | Count |\n|---|---:|\n"
           f"| Approved, real proto edit | {total_approved} |\n"
           f"| Approved anti-proposals (decision NOT to change the proto) | {len(anti_rows)} |\n"
           f"| Declined | {len(decline_rows)} |\n"
           f"| **Total reviewed** | {len(seed)} |\n")

out.append("\n## Changes by domain\n")
for domain in sorted(rows_by_domain.keys()):
    rows = rows_by_domain[domain]
    out.append(f"\n<details>\n<summary><strong>{domain}</strong> ({len(rows)} changes)</summary>\n")
    for pid, p, challenge, care, edit in sorted(rows, key=lambda r: r[0]):
        out.append(render_edit_section(pid, p, challenge, care, edit))
    out.append("</details>\n")

out.append("\n## Anti-proposals (decisions NOT to change the proto)\n")
out.append(
    "These proposals recommended *against* a change. Approving them means the "
    "proto stays as-is; no edit was made.\n"
)
for domain, pid, p, challenge in sorted(anti_rows, key=lambda r: (r[0], r[1])):
    out.append(f"- **`{pid}`** ({domain}): {p.get('title', '')}")

out.append("\n## Declined\n")
out.append("The skeptic recommended decline, or the proposal was independently rejected; no proto change was made.\n")
for domain, pid, p, challenge in sorted(decline_rows, key=lambda r: (r[0], r[1])):
    reason = challenge.get("problem", "") if challenge else ""
    out.append(f"- **`{pid}`** ({domain}): {p.get('title', '')}" + (f" — {truncate(reason, 200)}" if reason else ""))

print("\n".join(out))
