#!/bin/bash
# Runs the tests. The Command Line Tools sometimes fail to load the Swift Testing macros
# ("plugin for module 'TestingMacros' not found") right after a test file changes; that is a
# build-tool glitch, not a test failure, so retry it a couple of times.
cd "$(dirname "$0")"
for attempt in 1 2 3; do
    output="$(swift test "$@" 2>&1)"
    status=$?
    if [ $status -eq 0 ] || ! grep -q "plugin for module 'TestingMacros' not found" <<<"$output"; then
        printf '%s\n' "$output"
        exit $status
    fi
    echo "(TestingMacros glitch, retrying: attempt $attempt)" >&2
done
printf '%s\n' "$output"
exit $status
