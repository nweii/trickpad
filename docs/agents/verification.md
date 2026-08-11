# Verification

A step can report success it did not achieve, and the next step will believe it. These are the places in this project where that has happened.

## Proving a check works

A check that has never failed has not been tested. Break what it guards, confirm the check names the failure, then restore.

Commit before breaking anything. `git restore` and `git checkout` discard the sabotage and the fix together, and an uncommitted fix is gone.

Sabotage the exact failure the check exists for. A guard against two copies starting at once was tested by starting them one after another, which passes because the case it guards never occurs.

## Reading a build

`build.sh` prints the bundle path as part of signing, so output containing that path says nothing about whether it succeeded. Read the exit code.

A pipeline reports its last command. `grep` and `head` succeed on output from a command that failed.

## Verifying on hardware

Verify gesture work on both a Magic Trackpad and a Magic Mouse. They diverge in ways that hide bugs on one of them: the trackpad delivers frames after a lift and the mouse does not, so a lifecycle bug can present on one device and pass on the other for reasons unrelated to recognition.

Verify scroll behaviour in a native application. Electron applications coalesce small scroll deltas, so a leak plainly visible in BBEdit or Notes shows nothing in Obsidian.

A gesture that dispatches twice usually means two copies of the app are running. Count them first.

## Instrumenting a path

Reasoning about an unobserved mechanism produced two wrong diagnoses of one scroll bug before logging the path answered it in a single gesture. Where a defect involves timing across callbacks, event streams, or processes, log the decision and its inputs before proposing a cause.

The log outlives the session and the reasoning does not, which also makes the next occurrence cheap to diagnose.
