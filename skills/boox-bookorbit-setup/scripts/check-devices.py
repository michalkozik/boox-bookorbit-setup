#!/usr/bin/env python3
"""Validate references/devices.md: columns, allowed status, evidence for 'verified', no sensitive data.

Usage: check-devices.py [path/to/devices.md]
Exit code 0 when valid, 1 otherwise (messages on stderr).
"""
import os
import re
import sys

COLUMNS = ["Model", "Android", "ABI", "Display", "Firmware", "Status",
           "Developer options path", "Launcher step", "Notes"]
STATUSES = {"verified", "partial", "untested"}
SENSITIVE = [
    (re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+"), "e-mail address"),
    (re.compile(r"\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b"), "MAC address"),
    (re.compile(r"https?://"), "URL (server addresses must not be published)"),
    (re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"), "IP address"),
    (re.compile(r"\bSN[:= ]\s*[0-9A-Za-z]{8,}", re.I), "serial number"),
]


def table_rows(lines):
    rows = []
    for line in lines:
        if line.startswith("|") and not re.match(r"^\|[\s:|-]+\|$", line):
            rows.append([c.strip() for c in line.strip().strip("|").split("|")])
    return rows


def check(text):
    errors = []
    lines = text.splitlines()
    rows = table_rows(lines)
    if not rows or rows[0] != COLUMNS:
        errors.append("table header must be exactly: " + " | ".join(COLUMNS))
        return errors
    for row in rows[1:]:
        if len(row) != len(COLUMNS):
            errors.append("row has %d cells, expected %d: %s" % (len(row), len(COLUMNS), row[0] if row else "?"))
            continue
        data = dict(zip(COLUMNS, row))
        model = data["Model"]
        if not data["Android"].isdigit():
            errors.append("%s: Android must be a number" % model)
        if data["Status"] not in STATUSES:
            errors.append("%s: Status must be one of %s" % (model, sorted(STATUSES)))
        if data["Status"] == "verified":
            if len(data["Developer options path"]) < 15:
                errors.append("%s: verified needs a developer-options path" % model)
            if data["Launcher step"].lower().startswith("untested"):
                errors.append("%s: verified cannot have an untested launcher step" % model)
    for number, line in enumerate(lines, 1):
        if "Do not include" in line:
            continue
        for pattern, label in SENSITIVE:
            if pattern.search(line):
                errors.append("line %d: possible %s" % (number, label))
    return errors


def main(argv):
    path = argv[1] if len(argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "references", "devices.md")
    with open(path, encoding="utf-8") as handle:
        errors = check(handle.read())
    for message in errors:
        print("devices.md: " + message, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
