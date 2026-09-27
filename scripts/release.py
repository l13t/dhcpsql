#!/usr/bin/env python3
"""Plan a release from reachable vMAJOR.MINOR.PATCH tags and commit messages."""

import argparse
import os
from pathlib import Path
import re
import subprocess


VERSION = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def bump_level(message):
    header = re.match(r"([a-z]+)(?:\([^\r\n()]+\))?(!)?: .+", message, re.I)
    if not header:
        return 0
    if header[2] or re.search(r"^BREAKING[ -]CHANGE: .+", message, re.M):
        return 3
    return {"feat": 2, "fix": 1}.get(header[1].lower(), 0)


def plan():
    tags = []
    for tag in git("tag", "--merged", "HEAD").splitlines():
        match = re.fullmatch("v" + VERSION, tag)
        if match:
            tags.append((tuple(map(int, match.groups())), tag))
    if tags:
        base, tag = max(tags)
        revision = f"{tag}..HEAD"
    else:
        match = re.search(r"project\(udhcp-sql VERSION " + VERSION,
                          Path("CMakeLists.txt").read_text())
        if not match:
            raise ValueError("Cannot find the initial CMake version")
        base = tuple(map(int, match.groups()))
        revision = "HEAD"
    messages = git("log", "--format=%B%x00", revision).split("\0")
    level = max((bump_level(message.strip()) for message in messages), default=0)
    if not level:
        return ""
    major, minor, patch = base
    return {3: f"{major + 1}.0.0", 2: f"{major}.{minor + 1}.0",
            1: f"{major}.{minor}.{patch + 1}"}[level]


def set_version(version):
    if not re.fullmatch(VERSION, version):
        raise ValueError(f"Invalid release version: {version}")
    for filename, pattern, replacement in [
        ("CMakeLists.txt", r"(project\(udhcp-sql VERSION )[^ ]+",
         lambda m: m[1] + version),
        ("include/udhcp/version.h", r'(#define VERSION )"[^"]+"',
         lambda m: m[1] + f'"{version}"'),
    ]:
        path = Path(filename)
        content, count = re.subn(pattern, replacement, path.read_text())
        if count != 1:
            raise ValueError(f"Expected exactly one version in {filename}")
        path.write_text(content)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--set-version")
    args = parser.parse_args()
    if args.set_version:
        set_version(args.set_version)
    else:
        version = plan()
        print(f"Release version: {version or 'no release'}")
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a") as output:
                output.write(f"version={version}\n")
