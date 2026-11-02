#!/usr/bin/env python3
"""Run the permanent UC-09, UC-20 and UC-31 regression tests.

Scripted windows exercise production handlers without changing the installed app,
Dock settings or permissions. Unlike the original audit, this runner never injects
or rewrites fixtures. Exit 1 means a regression assertion failed.
"""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / ".build/use-case-audit"


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    command = ["swift", "test", "--filter", "auditUC"]
    result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    log = OUTPUT / "regressions.log"
    log.write_text(result.stdout)
    for line in result.stdout.splitlines():
        if "auditUC" in line or "Test run with" in line or "error:" in line:
            print(line)
    summary = {
        "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "mode": "permanent-regressions",
        "exit_code": result.returncode,
        "log": str(log),
    }
    (OUTPUT / "regressions-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary))
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
