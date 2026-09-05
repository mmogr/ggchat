#!/usr/bin/env bash
# No credential in any log line, ever. This is the static half: a log call
# may not interpolate an identifier that names a credential, and may not
# log a request's headers. The runtime half is
# OpenAICompatibleProviderTests.testNoCredentialEverReachesALogLine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
calls=$(grep -rnE --include='*.swift' '\.log\(|logger\.(debug|info|error|warning|notice|fault)\(' "$ROOT/Sources" "$ROOT/App" 2>/dev/null || true)
if hits=$(printf '%s\n' "$calls" | grep -E '\\\((.*)?(apiKey|token|ticket|secret|Authorization|allHTTPHeaderFields|httpBody)'); then
    echo "log: a log call touches a credential or a header:" >&2
    printf '%s\n' "$hits" >&2
    exit 1
fi
echo "log: ok"
