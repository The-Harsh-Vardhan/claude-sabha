# Sourced by every tests/test-*.sh right after "set -u". A test must never reach a real herdr (it opens workspaces
# and starts real claude sessions on the default herdr session): this puts tests/hermetic-bin (a fake) first on PATH,
# sets SABHA_TEST=1 and SABHA_HERDR_BIN (bin/sabha-herdr.sh then refuses any other herdr binary), and exits 2 when
# the fake is not the first herdr on PATH. A test that installs its own fake copy resets SABHA_HERDR_BIN to it.
SABHA_TEST=1
# a test run from inside a live sabha shell must not inherit its plan: the plan roster would replace the test's own
unset SABHA_PLAN
HERMETIC_BIN=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-bin
PATH=$HERMETIC_BIN:$PATH
SABHA_HERDR_BIN=$HERMETIC_BIN/herdr
# a private fake-herdr state dir and logs per test (never shared between runs); removed when the test exits, unless
# the test installs its own EXIT trap (it then sets its own FAKE_HERDR_DIR anyway)
HERMETIC_FAKE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sabha-fakeherdr.XXXXXX") || exit 2
FAKE_HERDR_DIR=$HERMETIC_FAKE_DIR
FAKE_HERDR_LOG=$FAKE_HERDR_DIR/log FAKE_HERDR_CALLS=$FAKE_HERDR_DIR/calls
trap 'rm -rf "$HERMETIC_FAKE_DIR"' EXIT
export SABHA_TEST SABHA_HERDR_BIN PATH HERMETIC_FAKE_DIR FAKE_HERDR_DIR FAKE_HERDR_LOG FAKE_HERDR_CALLS
if [[ $(command -v herdr) != "$SABHA_HERDR_BIN" ]]; then
  echo "hermetic: the fake herdr is not first on PATH ($(command -v herdr)); refusing to run tests" >&2
  exit 2
fi
