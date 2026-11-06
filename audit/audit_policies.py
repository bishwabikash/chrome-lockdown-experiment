import json
import re
import sys
from pathlib import Path

import yaml

if len(sys.argv) < 4:
    sys.exit("usage: audit_policies.py <policy_definitions_dir> <config.json> <milestone>")

defs_root = Path(sys.argv[1])
config = json.loads(Path(sys.argv[2]).read_text())
CURRENT = int(sys.argv[3])

index = {p.stem: p for p in defs_root.glob("*/*.yaml")}

LINUX_TOKENS = ("chrome.linux", "chrome.*")


def parse_supported(entries):
    out = []
    for e in entries or []:
        m = re.match(r"^([^:]+):(\d+)-(\d*)$", str(e).strip())
        if m:
            out.append((m.group(1), int(m.group(2)), int(m.group(3)) if m.group(3) else None))
        else:
            out.append((str(e), None, None))
    return out


def check_value(spec, value):
    items = spec.get("items")
    schema = spec.get("schema") or {}
    stype = schema.get("type")
    if stype == "array":
        if not isinstance(value, list):
            return f"expects array, got {type(value).__name__}"
        inner = ((schema.get("items") or {}).get("enum")) or []
        if inner:
            bad = [v for v in value if v not in inner]
            if bad:
                return f"invalid entries {bad}"
        return None
    if items:
        allowed = [i.get("value") for i in items]
        if value not in allowed:
            return f"value {value!r} not in {allowed}"
        return None
    if stype == "boolean" and not isinstance(value, bool):
        return f"expects boolean, got {type(value).__name__}"
    if stype == "integer" and not isinstance(value, int):
        return f"expects integer, got {type(value).__name__}"
    if stype == "string" and not isinstance(value, str):
        return f"expects string, got {type(value).__name__}"
    enum = schema.get("enum")
    if enum and value not in enum:
        return f"value {value!r} not in {enum}"
    return None


rows = []
for key, value in config.items():
    path = index.get(key)
    if path is None:
        rows.append((key, "MISSING", "not in Chromium policy definitions", ""))
        continue

    spec = yaml.safe_load(path.read_text()) or {}
    features = spec.get("features") or {}
    supported = parse_supported(spec.get("supported_on"))
    linux = [s for s in supported if s[0].startswith(LINUX_TOKENS)]

    flags = []
    if spec.get("deprecated"):
        flags.append("deprecated:true")
    if features.get("cloud_only"):
        flags.append("CLOUD_ONLY")
    if features.get("platform_only"):
        flags.append("platform_only")

    if not linux:
        plats = sorted({s[0] for s in supported}) or ["none"]
        status = "NOT_ON_LINUX"
        detail = "supported_on: " + ",".join(plats)
    else:
        ends = [s[2] for s in linux]
        if all(e is not None and e < CURRENT for e in ends):
            status = "REMOVED"
            detail = "linux support ended at " + ",".join(str(e) for e in ends)
        else:
            status = "OK"
            detail = "linux " + ",".join(
                f"{s[1]}-{s[2] if s[2] else ''}" for s in linux
            )

    if "CLOUD_ONLY" in flags:
        status = "CLOUD_ONLY"
    elif spec.get("deprecated") and status == "OK":
        status = "DEPRECATED"

    verr = check_value(spec, value)
    if verr and status in ("OK", "DEPRECATED"):
        status = "BAD_VALUE"
        detail = verr

    rows.append((key, status, detail, " ".join(flags)))

order = {
    "MISSING": 0,
    "REMOVED": 1,
    "CLOUD_ONLY": 2,
    "NOT_ON_LINUX": 3,
    "BAD_VALUE": 4,
    "DEPRECATED": 5,
    "OK": 6,
}
rows.sort(key=lambda r: (order.get(r[1], 9), r[0]))

width = max(len(r[0]) for r in rows)
for key, status, detail, flags in rows:
    sunset = "  <-- SUNSETTING" if status == "OK" and re.search(r"-1\d\d$", detail) else ""
    print(f"{key:<{width}}  {status:<13} {detail}  {flags}{sunset}".rstrip())

print()
counts = {}
for _, status, _, _ in rows:
    counts[status] = counts.get(status, 0) + 1
print("summary:", ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
print(f"audited against Chrome milestone {CURRENT}")

problems = [r for r in rows if r[1] != "OK"]
if problems:
    print(f"\nFAIL: {len(problems)} policies need attention")
    sys.exit(1)
print("\nPASS: all policies valid")
