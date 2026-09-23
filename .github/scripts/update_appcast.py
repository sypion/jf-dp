#!/usr/bin/env python3
import argparse
import pathlib
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("appcast", type=pathlib.Path)
    parser.add_argument("--notes-file", required=True, type=pathlib.Path, help="Release notes (Markdown)")
    args = parser.parse_args()

    ET.register_namespace("sparkle", SPARKLE)
    tree = ET.parse(args.appcast)
    notes = args.notes_file.read_text().strip()
    for item in tree.getroot().iter("item"):
        description = item.find("description")
        if description is not None:
            item.remove(description)
        if notes:
            description = ET.SubElement(item, "description", {f"{{{SPARKLE}}}format": "markdown"})
            description.text = notes

    tree.write(args.appcast, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main()
