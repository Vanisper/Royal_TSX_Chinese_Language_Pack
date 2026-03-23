#!/usr/bin/env python3

from __future__ import annotations

import argparse
import html
import re
import sys
from pathlib import Path
from xml.etree import ElementTree as ET


DEFAULT_ROOT = Path("Plugins-6.4.1.1000")
TARGET_NAME = "PluginInfo.xml"
SOURCE_NAME = "PluginInfo.source.xml"
SAFE_ASCII_FIELDS = ("Name", "ShortDescription", "LicenseType")
DESCRIPTION_PATTERN = re.compile(
    r"(<Description><!\[CDATA\[)(.*?)(\]\]></Description>)",
    re.DOTALL,
)


def encode_non_ascii(text: str) -> str:
    return "".join(f"&#x{ord(ch):X};" if ord(ch) > 127 else ch for ch in text)


def replace_description_content(xml_text: str, transform) -> str:
    match = DESCRIPTION_PATTERN.search(xml_text)
    if not match:
        raise ValueError("Missing <Description><![CDATA[...]]></Description> block")

    start, end = match.span(2)
    return xml_text[:start] + transform(match.group(2)) + xml_text[end:]


def ensure_ascii_safe_fields(xml_text: str, source_path: Path) -> None:
    root = ET.fromstring(xml_text)
    for field in SAFE_ASCII_FIELDS:
        value = root.findtext(field)
        if value is None:
            raise ValueError(f"{source_path}: missing <{field}>")
        if any(ord(ch) > 127 for ch in value):
            raise ValueError(
                f"{source_path}: <{field}> contains non-ASCII text. "
                "These fields should stay English/safe ASCII to avoid Royal TSX rendering bugs."
            )


def validate_xml(xml_text: str, source_path: Path) -> None:
    try:
        ET.fromstring(xml_text)
    except ET.ParseError as exc:
        raise ValueError(f"{source_path}: invalid XML: {exc}") from exc


def source_paths(root: Path) -> list[Path]:
    return sorted(root.glob(f"*.plugin/PluginInfo/{SOURCE_NAME}"))


def target_paths(root: Path) -> list[Path]:
    return sorted(root.glob(f"*.plugin/PluginInfo/{TARGET_NAME}"))


def build_file(source_path: Path) -> str:
    source_text = source_path.read_text(encoding="utf-8")
    validate_xml(source_text, source_path)
    ensure_ascii_safe_fields(source_text, source_path)
    output_text = replace_description_content(source_text, encode_non_ascii)
    validate_xml(output_text, source_path)
    return output_text


def command_bootstrap(root: Path, overwrite: bool) -> int:
    created = 0
    skipped = 0

    for target_path in target_paths(root):
        source_path = target_path.with_name(SOURCE_NAME)
        if source_path.exists() and not overwrite:
            skipped += 1
            continue

        target_text = target_path.read_text(encoding="utf-8")
        validate_xml(target_text, target_path)
        source_text = replace_description_content(target_text, html.unescape)
        validate_xml(source_text, source_path)
        source_path.write_text(source_text, encoding="utf-8")
        created += 1
        print(source_path.as_posix())

    print(f"bootstrapped={created} skipped={skipped}", file=sys.stderr)
    return 0


def command_build(root: Path, check: bool) -> int:
    outputs_changed = 0
    for source_path in source_paths(root):
        target_path = source_path.with_name(TARGET_NAME)
        output_text = build_file(source_path)

        if check:
            current = target_path.read_text(encoding="utf-8") if target_path.exists() else ""
            if current != output_text:
                print(f"outdated: {target_path.as_posix()}", file=sys.stderr)
                outputs_changed += 1
            continue

        current = target_path.read_text(encoding="utf-8") if target_path.exists() else ""
        if current != output_text:
            target_path.write_text(output_text, encoding="utf-8")
            outputs_changed += 1
            print(target_path.as_posix())

    if check:
        if outputs_changed:
            print(f"check_failed={outputs_changed}", file=sys.stderr)
            return 1
        print("check_ok", file=sys.stderr)
        return 0

    print(f"updated={outputs_changed}", file=sys.stderr)
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Bootstrap and generate Royal TSX PluginInfo.xml files."
    )
    parser.add_argument(
        "command",
        choices=("bootstrap", "build", "check"),
        help="bootstrap readable source files, build final PluginInfo.xml files, or check if generated files are up to date",
    )
    parser.add_argument(
        "--root",
        default=str(DEFAULT_ROOT),
        help=f"plugin root directory (default: {DEFAULT_ROOT})",
    )
    parser.add_argument(
        "--overwrite-source",
        action="store_true",
        help="allow bootstrap to overwrite existing PluginInfo.source.xml files",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root)

    if args.command == "bootstrap":
        return command_bootstrap(root, overwrite=args.overwrite_source)
    if args.command == "build":
        return command_build(root, check=False)
    return command_build(root, check=True)


if __name__ == "__main__":
    raise SystemExit(main())
