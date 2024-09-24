# Nimbus
# Copyright (c) 2024 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
#  * MIT license ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.warning[UnusedImport]: off.}

# Note: These tests are separated because they require a custom merge block
# number defined at compile time. Once runtime chain config gets added these
# tests can be compiled together with all the other portal tests.
import ./test_historical_hashes_accumulator, ./test_history_network
