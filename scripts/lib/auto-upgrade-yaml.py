#!/usr/bin/env python3
"""Parse scripts/auto-upgrade.yaml (restricted mapping-list schema)."""

from __future__ import annotations

import argparse
import json
import re
import shlex
import sys
from pathlib import Path

ALLOWED_KEYS = {
    "id",
    "class",
    "env_file",
    "var",
    "image_prefix",
    "compose_dir",
    "chain_links",
    "source_type",
    "source_repo",
    "tag_prefix",
    "exclude",
    "health_path",
    "health_port_var",
    "health_bind_var",
    "image_tag_from",
}

REQUIRED_KEYS = {
    "id",
    "class",
    "env_file",
    "var",
    "image_prefix",
    "compose_dir",
    "source_type",
    "source_repo",
    "tag_prefix",
}


def coerce(value: str):
    value = value.strip()
    if value in ("true", "True"):
        return True
    if value in ("false", "False"):
        return False
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def load_chains(path: Path) -> list[dict]:
    chains: list[dict] = []
    current: dict | None = None
    for raw in path.read_text().splitlines():
        stripped = raw.split("#", 1)[0].rstrip()
        if not stripped.strip():
            continue
        if stripped.strip() == "chains:":
            continue
        item = re.match(r"^  - (\w+):\s*(.*)$", stripped)
        if item:
            if current is not None:
                chains.append(current)
            current = {item.group(1): coerce(item.group(2))}
            continue
        field = re.match(r"^    (\w+):\s*(.*)$", stripped)
        if field and current is not None:
            current[field.group(1)] = coerce(field.group(2))
            continue
        raise SystemExit(f"unparsed yaml line: {raw}")
    if current is not None:
        chains.append(current)

    for chain in chains:
        unknown = set(chain) - ALLOWED_KEYS
        if unknown:
            raise SystemExit(f"{chain.get('id', '?')}: unknown keys: {sorted(unknown)}")
        missing = REQUIRED_KEYS - set(chain)
        if missing:
            raise SystemExit(f"{chain.get('id', '?')}: missing keys: {sorted(missing)}")
        if chain["class"] != "tag-only":
            raise SystemExit(f"{chain['id']}: class must be tag-only (got {chain['class']})")
        tag_from = chain.get("image_tag_from")
        if tag_from is not None and tag_from != "release_body":
            raise SystemExit(
                f"{chain['id']}: image_tag_from must be release_body (got {tag_from})"
            )
    return chains


def series_from_tag(tag: str) -> str:
    match = re.search(r"^(.*?)(\d+)\.(\d+)", tag)
    if not match:
        raise SystemExit(f"cannot derive major.minor series from tag: {tag}")
    return f"{match.group(1)}{match.group(2)}.{match.group(3)}"


def same_series(tag: str, series: str) -> bool:
    return re.match(re.escape(series) + r"($|[.\-])", tag) is not None


def excluded(tag: str, exclude: str) -> bool:
    parts = [p for p in exclude.split(",") if p]
    return any(part in tag for part in parts)


def docker_tag_from_release_body(body: str, image_prefix: str, git_tag: str) -> str:
    """Nitro-style pin: git tag v3.11.3, docker tag v3.11.3-<hash> (not -validator)."""
    pattern = re.compile(
        re.escape(image_prefix) + r"(v\d+\.\d+\.\d+-[0-9a-f]+)(?![\w-])"
    )
    found = sorted(
        {tag for tag in pattern.findall(body) if tag.startswith(git_tag + "-")}
    )
    if len(found) != 1:
        raise SystemExit(
            f"expected one docker tag for {git_tag} in release body, found {found!r}"
        )
    return found[0]


def dump_export(chain: dict) -> None:
    for key in sorted(chain):
        value = chain[key]
        if isinstance(value, bool):
            rendered = "true" if value else "false"
        else:
            rendered = str(value)
        print(f"AUTO_{key.upper()}={shlex.quote(rendered)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--file",
        default=str(Path(__file__).resolve().parents[1] / "auto-upgrade.yaml"),
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list")
    export_p = sub.add_parser("export")
    export_p.add_argument("id")
    json_p = sub.add_parser("json")
    json_p.add_argument("id")
    series_p = sub.add_parser("series")
    series_p.add_argument("tag")
    filter_p = sub.add_parser("filter-series")
    filter_p.add_argument("--current", required=True)
    filter_p.add_argument("--exclude", default="")
    body_p = sub.add_parser("docker-tag-from-body")
    body_p.add_argument("--image-prefix", required=True)
    body_p.add_argument("--git-tag", required=True)

    args = parser.parse_args()
    path = Path(args.file)
    if args.cmd == "series":
        print(series_from_tag(args.tag))
        return 0
    if args.cmd == "docker-tag-from-body":
        print(
            docker_tag_from_release_body(
                sys.stdin.read(), args.image_prefix, args.git_tag
            )
        )
        return 0
    if args.cmd == "filter-series":
        series = series_from_tag(args.current)
        for line in sys.stdin:
            tag = line.strip()
            if not tag:
                continue
            if excluded(tag, args.exclude):
                continue
            if same_series(tag, series):
                print(tag)
        return 0

    chains = load_chains(path)
    if args.cmd == "list":
        for chain in chains:
            print(chain["id"])
        return 0

    match = next((c for c in chains if c["id"] == args.id), None)
    if match is None:
        raise SystemExit(f"unknown chain id: {args.id}")
    if args.cmd == "export":
        dump_export(match)
        return 0
    print(json.dumps(match, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
