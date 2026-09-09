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
    "apply_group",
    "chain_links",
    "source_type",
    "source_repo",
    "tag_prefix",
    "strip_git_prefix",
    "exclude",
    "health_path",
    "health_port_var",
    "health_bind_var",
    "image_tag_from",
    "image_tag_suffix",
    "compose_build",
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

    ids = set()
    groups: dict[str, list[dict]] = {}
    for chain in chains:
        unknown = set(chain) - ALLOWED_KEYS
        if unknown:
            raise SystemExit(f"{chain.get('id', '?')}: unknown keys: {sorted(unknown)}")
        missing = REQUIRED_KEYS - set(chain)
        if missing:
            raise SystemExit(f"{chain.get('id', '?')}: missing keys: {sorted(missing)}")
        if chain["class"] != "tag-only":
            raise SystemExit(f"{chain['id']}: class must be tag-only (got {chain['class']})")
        if chain["id"] in ids:
            raise SystemExit(f"duplicate chain id: {chain['id']}")
        ids.add(chain["id"])
        tag_from = chain.get("image_tag_from")
        if tag_from is not None and tag_from != "release_body":
            raise SystemExit(
                f"{chain['id']}: image_tag_from must be release_body (got {tag_from})"
            )
        suffix = chain.get("image_tag_suffix")
        if suffix and tag_from != "release_body":
            raise SystemExit(
                f"{chain['id']}: image_tag_suffix requires image_tag_from: release_body"
            )
        group = chain.get("apply_group")
        if group:
            groups.setdefault(group, []).append(chain)

    for group, rows in groups.items():
        compose_dirs = {row["compose_dir"] for row in rows}
        if len(compose_dirs) != 1:
            raise SystemExit(
                f"apply_group {group}: compose_dir must be shared, got {sorted(compose_dirs)}"
            )
        env_files = {row["env_file"] for row in rows}
        if len(env_files) != 1:
            raise SystemExit(
                f"apply_group {group}: env_file must be shared, got {sorted(env_files)}"
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


def pin_form(tag: str, strip_prefix: str) -> str:
    if strip_prefix and tag.startswith(strip_prefix):
        return tag[len(strip_prefix) :]
    return tag


def docker_tag_from_release_body(
    body: str, image_prefix: str, git_tag: str, suffix: str = ""
) -> str:
    """Nitro-style pin: git tag v3.11.3, docker tag v3.11.3-<hash> (optional -validator)."""
    hash_tag = r"(v\d+\.\d+\.\d+-[0-9a-f]+)"
    if suffix:
        pattern = re.compile(
            re.escape(image_prefix) + hash_tag + re.escape(suffix) + r"(?![\w-])"
        )
        found = sorted(
            {
                tag + suffix
                for tag in pattern.findall(body)
                if tag.startswith(git_tag + "-")
            }
        )
    else:
        pattern = re.compile(re.escape(image_prefix) + hash_tag + r"(?![\w-])")
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


def apply_targets(chains: list[dict]) -> dict[str, list[str]]:
    targets: dict[str, list[str]] = {}
    for chain in chains:
        key = chain.get("apply_group") or chain["id"]
        targets.setdefault(key, []).append(chain["id"])
    return targets


def resolve_apply_ids(chains: list[dict], arg: str) -> list[str]:
    exact = next((c for c in chains if c["id"] == arg), None)
    if exact is not None:
        return [exact["id"]]
    grouped = [c["id"] for c in chains if c.get("apply_group") == arg]
    if grouped:
        return grouped
    raise SystemExit(f"unknown chain id or apply_group: {arg}")


def pin_vars_for_env(chains: list[dict], env_file: str) -> list[str]:
    vars_: list[str] = []
    for chain in chains:
        if chain["env_file"] == env_file and chain["var"] not in vars_:
            vars_.append(chain["var"])
    return vars_


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--file",
        default=str(Path(__file__).resolve().parents[1] / "auto-upgrade.yaml"),
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list")
    sub.add_parser("list-apply")
    export_p = sub.add_parser("export")
    export_p.add_argument("id")
    json_p = sub.add_parser("json")
    json_p.add_argument("id")
    apply_p = sub.add_parser("apply-ids")
    apply_p.add_argument("id")
    pin_vars_p = sub.add_parser("pin-vars")
    pin_vars_p.add_argument("--env-file", required=True)
    series_p = sub.add_parser("series")
    series_p.add_argument("tag")
    pin_form_p = sub.add_parser("pin-form")
    pin_form_p.add_argument("tag")
    pin_form_p.add_argument("--strip-prefix", default="")
    filter_p = sub.add_parser("filter-series")
    filter_p.add_argument("--current", required=True)
    filter_p.add_argument("--exclude", default="")
    filter_p.add_argument("--strip-prefix", default="")
    body_p = sub.add_parser("docker-tag-from-body")
    body_p.add_argument("--image-prefix", required=True)
    body_p.add_argument("--git-tag", required=True)
    body_p.add_argument("--suffix", default="")

    args = parser.parse_args()
    path = Path(args.file)
    if args.cmd == "series":
        print(series_from_tag(args.tag))
        return 0
    if args.cmd == "pin-form":
        print(pin_form(args.tag, args.strip_prefix))
        return 0
    if args.cmd == "docker-tag-from-body":
        print(
            docker_tag_from_release_body(
                sys.stdin.read(), args.image_prefix, args.git_tag, args.suffix
            )
        )
        return 0
    if args.cmd == "filter-series":
        series = series_from_tag(args.current)
        for line in sys.stdin:
            tag = line.strip()
            if not tag:
                continue
            comparable = pin_form(tag, args.strip_prefix)
            if excluded(tag, args.exclude) or excluded(comparable, args.exclude):
                continue
            if same_series(comparable, series):
                print(tag)
        return 0

    chains = load_chains(path)
    if args.cmd == "list":
        for chain in chains:
            print(chain["id"])
        return 0
    if args.cmd == "list-apply":
        targets = apply_targets(chains)
        for key in sorted(targets):
            ids = targets[key]
            if len(ids) == 1 and ids[0] == key:
                print(key)
            else:
                print(f"{key} ({', '.join(ids)})")
        return 0
    if args.cmd == "apply-ids":
        for chain_id in resolve_apply_ids(chains, args.id):
            print(chain_id)
        return 0
    if args.cmd == "pin-vars":
        vars_ = pin_vars_for_env(chains, args.env_file)
        if not vars_:
            raise SystemExit(f"no pin vars for env_file: {args.env_file}")
        for name in vars_:
            print(name)
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
