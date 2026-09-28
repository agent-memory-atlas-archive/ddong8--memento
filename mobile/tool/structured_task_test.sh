#!/bin/sh
# Runs test/collector/structured_task_test.dart with a fake `claude-fake-memento`
# on PATH that replays a recorded stream-json run and waits for a follow-up.
set -e
cd "$(dirname "$0")/.."
dir=$(mktemp -d)
fixture="$(pwd)/test/collector/fixtures/claude_stream.jsonl"
cat > "$dir/claude-fake-memento" <<EOF
#!/bin/sh
out="$dir/claude_stdin.txt"
IFS= read -r first; printf '%s\n' "\$first" > "\$out"
head -n 5 "$fixture"
IFS= read -r second && printf '%s\n' "\$second" >> "\$out"
tail -n +6 "$fixture"
cat > /dev/null
EOF
chmod +x "$dir/claude-fake-memento"
FAKE_AGENT_DIR="$dir" PATH="$dir:$PATH" flutter test test/collector/structured_task_test.dart
rm -rf "$dir"
