#!/usr/bin/env python3
"""Adds a release's plugin builds to manifest.json, the Jellyfin plugin repository file servers read."""

import argparse
import datetime
import hashlib
import json
import pathlib
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "manifest.json"
PLUGIN_PROJECT = ROOT / "src/Jellyfin.Plugin.DiscordPresence/Jellyfin.Plugin.DiscordPresence.csproj"


def builds() -> list[tuple[str, str]]:
    """(PluginRevision, targetAbi) for each target framework: one build per Jellyfin release line."""
    project = ET.parse(PLUGIN_PROJECT).getroot()
    groups = {g.get("Condition", "").replace(" ", ""): g for g in project.findall("PropertyGroup")}
    result = []
    for framework in project.findtext("PropertyGroup/TargetFrameworks", "").split(";"):
        group = groups.get(f"'$(TargetFramework)'=='{framework}'")
        jellyfin = group.findtext("JellyfinVersion") if group is not None else None
        revision = group.findtext("PluginRevision") if group is not None else None
        if not jellyfin or not revision:
            raise SystemExit(f"{PLUGIN_PROJECT} has no JellyfinVersion and PluginRevision for {framework}")
        # The oldest server this build runs on: the Jellyfin version it compiles against.
        major, minor = jellyfin.split(".")[:2]
        result.append((revision, f"{major}.{minor}.0.0"))
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="The release's three-part version, e.g. 1.2.0")
    parser.add_argument("--dist", required=True, type=pathlib.Path, help="Folder with the jf-dp_<version>.<revision>.zip builds")
    parser.add_argument("--url-prefix", required=True, help="Where servers download the zips from, ending in /")
    parser.add_argument("--changelog-file", type=pathlib.Path, help="Release notes (Markdown)")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    plugin = manifest[0]
    existing = {v["version"]: v for v in plugin["versions"]}
    changelog = args.changelog_file.read_text().strip() if args.changelog_file else ""
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    entries = []
    for revision, target_abi in builds():
        version = f"{args.version}.{revision}"
        zip_name = f"jf-dp_{version}.zip"
        # Jellyfin verifies downloads against this MD5 before installing.
        checksum = hashlib.md5((args.dist / zip_name).read_bytes()).hexdigest()
        previous = existing.get(version)
        entries.append({
            "version": version,
            "changelog": changelog,
            "targetAbi": target_abi,
            "sourceUrl": args.url_prefix + zip_name,
            "checksum": checksum,
            # Editing the release notes later keeps the release date.
            "timestamp": previous["timestamp"] if previous and previous["checksum"] == checksum else now,
        })

    # Re-running a release replaces its entries instead of duplicating them. Newest first.
    added = {e["version"] for e in entries}
    versions = [v for v in plugin["versions"] if v["version"] not in added] + entries
    versions.sort(key=lambda v: tuple(int(p) for p in v["version"].split(".")), reverse=True)
    plugin["versions"] = versions

    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    for e in entries:
        print(f"Added {e['version']} (targetAbi {e['targetAbi']}, md5 {e['checksum']})")


if __name__ == "__main__":
    main()
