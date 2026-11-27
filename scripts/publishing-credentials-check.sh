#!/bin/zsh
# Exercises publishing credential delivery with a stub 1Password CLI and
# isolated package paths, without reading secrets or contacting any service.
set -euo pipefail

ROOT="${0:A:h:h}"
python3 - "$ROOT" <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

source_root = Path(sys.argv[1])
work_root = Path(tempfile.mkdtemp(prefix="trickpad-credentials-check-"))
fixture_root = work_root / "repo"
scripts = fixture_root / "scripts"
scripts.mkdir(parents=True)
(fixture_root / "build").mkdir()
bin_dir = work_root / "bin"
bin_dir.mkdir()
log_file = work_root / "op.jsonl"
config_file = fixture_root / ".1password-environment"
environment_id = "00000000-0000-0000-0000-000000000001"

for script in ("publish.sh", "storefront.sh"):
    shutil.copy2(source_root / "scripts" / script, scripts / script)
(scripts / "build.sh").write_text(
    'SPARKLE_FEED_URL="https://updates.thirdwind.fyi/trickpad/9zvff4/appcast.xml"\n'
)
op = bin_dir / "op"
op.write_text('''#!/usr/bin/env python3
# Records invocation and optionally supplies fake publishing credentials.
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
with Path(os.environ["OP_TEST_LOG"]).open("a") as output:
    output.write(json.dumps(args) + "\\n")
if os.environ["OP_TEST_MODE"] == "deny":
    print("test authorization denied", file=sys.stderr)
    sys.exit(57)
assert args[:4] == ["run", "--environment", os.environ["OP_TEST_ENVIRONMENT"], "--"]
expected_account = os.environ.get("OP_TEST_EXPECTED_ACCOUNT")
if expected_account:
    assert os.environ.get("OP_ACCOUNT") == expected_account, "OP_ACCOUNT was not preserved"
env = os.environ.copy()
if os.environ["OP_TEST_MODE"] == "inject":
    env.update(R2_ACCESS_KEY_ID="test-access", R2_SECRET_ACCESS_KEY="test-secret",
               POLAR_ACCESS_TOKEN="test-polar")
os.execvpe(args[4], args[4:], env)
''')
op.chmod(0o755)

credential_names = ("R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "POLAR_ACCESS_TOKEN")
base_env = {key: value for key, value in os.environ.items() if key not in credential_names}
base_env.update(
    PATH=str(bin_dir) + os.pathsep + os.environ["PATH"],
    OP_TEST_LOG=str(log_file),
    OP_TEST_ENVIRONMENT=environment_id,
    OP_TEST_MODE="inject",
)

def run(script, args=(), **env_values):
    env = base_env | env_values
    log_file.write_text("")
    result = subprocess.run([str(scripts / script), *args], env=env,
                            text=True, capture_output=True, timeout=5)
    calls = [json.loads(line) for line in log_file.read_text().splitlines()]
    return result, calls

def expect(condition, message, result):
    if not condition:
        raise AssertionError(f"{message}\nexit={result.returncode}\n{result.stdout}{result.stderr}")

for script, required_names, artifact_message in (
    ("publish.sh", ("R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"), "Missing packaged appcast"),
    ("storefront.sh", ("POLAR_ACCESS_TOKEN",), "No packaged DMG"),
):
    result, calls = run(script, ("--help",))
    expect(result.returncode == 0 and not calls, f"{script}: help requested credentials", result)

    result, calls = run(script, ("--yes",))
    expect(result.returncode == 2 and not calls,
           f"{script}: invalid approval flags requested credentials", result)

    result, calls = run(script)
    expect(result.returncode == 1 and ".1password-environment" in result.stderr and not calls,
           f"{script}: missing configuration was not actionable", result)

    config_file.write_text("invalid environment id\n")
    result, calls = run(script)
    expect(result.returncode == 1 and "must contain only" in result.stderr and not calls,
           f"{script}: malformed configuration reached 1Password", result)

    config_file.write_text(environment_id + "\n")
    result, calls = run(script, OP_TEST_MODE="deny")
    expect(result.returncode == 57 and len(calls) == 1,
           f"{script}: authorization failure was not preserved", result)

    result, calls = run(script, OP_TEST_MODE="empty")
    expect(result.returncode == 1 and len(calls) == 1 and
           "1Password Environment must contain" in result.stderr and
           all(name in result.stderr for name in required_names),
           f"{script}: missing delivered credentials recursed or hid the missing names", result)

    result, calls = run(script)
    expect(result.returncode == 1 and len(calls) == 1 and artifact_message in result.stderr,
           f"{script}: delivered credentials did not reach the original entry point", result)

    result, calls = run(script, OP_ACCOUNT="test-account", OP_TEST_EXPECTED_ACCOUNT="test-account")
    expect(result.returncode == 1 and len(calls) == 1 and artifact_message in result.stderr,
           f"{script}: manual 1Password account selection was not preserved", result)

    result, calls = run(script, ("--publish", "1.0.0", "--yes"))
    expect(result.returncode == 1 and len(calls) == 1 and
           calls[0][-4:] == [str(scripts / script), "--publish", "1.0.0", "--yes"],
           f"{script}: re-execution lost the original publish arguments", result)

    ambient = {name: "test-ambient" for name in required_names}
    result, calls = run(script, **ambient)
    expect(result.returncode == 1 and not calls and artifact_message in result.stderr,
           f"{script}: ambient credentials unnecessarily invoked 1Password", result)

    config_file.rename(work_root / (script + ".config"))

print("publishing credentials check passed")
PY
