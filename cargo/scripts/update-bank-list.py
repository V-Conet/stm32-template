#!/usr/bin/env python3
"""Regenerate the `bank_configurable` list in pre-script.rhai.

embassy-stm32's build script refuses to build chips whose flash can be
configured as single or dual bank unless the `single-bank` or `dual-bank`
feature is selected, while it panics if either feature is used on a chip that
has a fixed layout. Which chips are which is only known from stm32-metapac's
chip metadata, so the list is embedded in the template's pre-script.

Run this after bumping embassy-stm32 / stm32-metapac versions:

    python3 scripts/update-bank-list.py [--metapac PATH] [--embassy PATH]

By default the newest `stm32-metapac-*` / `embassy-stm32-*` source trees in the
local cargo registry are used.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys

TEMPLATE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRE_SCRIPT = os.path.join(TEMPLATE_DIR, "pre-script.rhai")
REGISTRY_GLOB = os.path.expanduser("~/.cargo/registry/src/*")


def newest(base: str) -> str:
    matches = sorted(glob.glob(os.path.join(REGISTRY_GLOB, base + "-*")))
    matches = [m for m in matches if os.path.isdir(m)]
    if not matches:
        sys.exit(f"no {base} source found in the cargo registry; pass --{base.split('-')[0]}")
    return max(matches, key=lambda p: version_key(os.path.basename(p)))


def version_key(name: str) -> tuple[int, ...]:
    version = name.rsplit("-", 1)[-1]
    return tuple(int(x) if x.isdigit() else 0 for x in re.split(r"[.]", version))


def parse_memory_options(source: str) -> list[list[str]] | None:
    """Return the list of memory layout options from a chip metadata.rs file."""
    start = source.find("memory: &[")
    if start < 0:
        return None
    pos = start + len("memory: ")
    depth = 0
    end = None
    for i in range(pos, len(source)):
        if source[i] == "[":
            depth += 1
        elif source[i] == "]":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        return None

    body = source[pos:end]
    options: list[str] = []
    depth = 0
    option_start = None
    for i, ch in enumerate(body):
        if ch == "[":
            depth += 1
            if depth == 2:
                option_start = i
        elif ch == "]":
            if depth == 2 and option_start is not None:
                options.append(body[option_start : i + 1])
                option_start = None
            depth -= 1
    return options


def embassy_features(embassy_dir: str) -> set[str]:
    features = set()
    with open(os.path.join(embassy_dir, "Cargo.toml"), encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^(stm32[fgh][0-9][a-z0-9]*)(?:-cm[47])? = ", line)
            if m:
                features.add(m.group(1))
    return features


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--metapac", help="path to a stm32-metapac source tree")
    ap.add_argument("--embassy", help="path to an embassy-stm32 source tree")
    args = ap.parse_args()

    metapac = args.metapac or newest("stm32-metapac")
    embassy = args.embassy or newest("embassy-stm32")
    chips_dir = os.path.join(metapac, "src", "chips")
    if not os.path.isdir(chips_dir):
        sys.exit(f"{chips_dir} not found")

    supported = embassy_features(embassy)
    configurable: list[str] = []
    dual_only: list[str] = []

    for chip in sorted(os.listdir(chips_dir)):
        meta = os.path.join(chips_dir, chip, "metadata.rs")
        if not os.path.isfile(meta) or chip not in supported:
            continue
        options = parse_memory_options(open(meta, encoding="utf-8").read())
        if options is None:
            continue
        if len(options) > 1:
            if any("BANK_2" not in opt for opt in options):
                configurable.append(chip)
            else:
                dual_only.append(chip)

    if dual_only:
        sys.exit(
            "chips with a dual-bank-only layout found: "
            + ", ".join(dual_only)
            + "\nthe template would need to select the 'dual-bank' feature for them"
        )

    if not configurable:
        sys.exit("no bank-configurable chips found; refusing to write an empty list")

    lines = "\n".join(
        "    " + ", ".join('"%s"' % chip for chip in configurable[i : i + 6]) + ","
        for i in range(0, len(configurable), 6)
    )
    block = "let bank_configurable = [\n" + lines + "\n];"

    script = open(PRE_SCRIPT, encoding="utf-8").read()
    new_script, substitutions = re.subn(
        r"let bank_configurable = \[.*?\n\];", block, script, count=1, flags=re.DOTALL
    )
    if substitutions != 1:
        sys.exit("could not find the `bank_configurable` list in pre-script.rhai")

    open(PRE_SCRIPT, "w", encoding="utf-8").write(new_script)
    print(
        f"updated {PRE_SCRIPT}: {len(configurable)} bank-configurable chips "
        f"(embassy-stm32 {os.path.basename(embassy)}, {os.path.basename(metapac)})"
    )


if __name__ == "__main__":
    main()
