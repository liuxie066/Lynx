#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Some Command Line Tools versions contain TestingMacros but do not auto-discover it.
lynx_swift_bin=$(dirname "$(xcrun --find swiftc)")
lynx_testing_plugin="$lynx_swift_bin/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$lynx_testing_plugin" ]]; then
  swift test -Xswiftc -load-plugin-library -Xswiftc "$lynx_testing_plugin"
else
  swift test
fi
