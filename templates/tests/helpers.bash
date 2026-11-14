# shellcheck shell=bash
# Test helpers of this repository's own tests: the standard's lib.bash first, as in every
# repository of the standard, then the helpers these tests add or redefine.
# shellcheck source=.github/standard/tests/lib.bash
source "${BASH_SOURCE[0]%/*}/../.github/standard/tests/lib.bash"
