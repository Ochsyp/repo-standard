# shellcheck shell=bash
# Test helpers of repo-standard's own tests of tools/: the standard's lib.bash first, as in every
# repository of the standard, then what these tests add.
# shellcheck source=.github/standard/tests/lib.bash
source "${BASH_SOURCE[0]%/*}/../.github/standard/tests/lib.bash"
