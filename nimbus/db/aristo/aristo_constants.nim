# nimbus-eth1
# Copyright (c) 2023-2024 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
#    http://www.apache.org/licenses/LICENSE-2.0)
#  * MIT license ([LICENSE-MIT](LICENSE-MIT) or
#    http://opensource.org/licenses/MIT)
# at your option. This file may not be copied, modified, or distributed
# except according to those terms.

{.push raises: [].}

import
  std/sets,
  eth/common,
  ./aristo_desc/desc_identifiers

const
  EmptyBlob* = seq[byte].default
    ## Useful shortcut (borrowed from `sync/snap/constants.nim`)

  EmptyVidSeq* = seq[VertexID].default
    ## Useful shortcut

  EmptyVidSet* = EmptyVidSeq.toHashSet
    ## Useful shortcut

  VOID_CODE_HASH* = EMPTY_CODE_HASH
    ## Equivalent of `nil` for `Account` object code hash field

  VOID_HASH_KEY* = HashKey()
    ## Void equivalent for Merkle hash value

  VOID_PATH_ID* = PathID()
    ## Void equivalent for Merkle hash value

  LEAST_FREE_VID* = 100
    ## Vids smaller are used as known state roots and cannot be recycled. Only
    ## the `VertexID(1)` state root is used by the `Aristo` methods. The other
    ## numbers smaller than `LEAST_FREE_VID` may be used by application
    ## functions with fixed assignments of the type of a state root (e.g. for
    ## a receipt or a transaction root.)

static:
  # must stay away from `VertexID(1)` and `VertexID(2)`
  doAssert 2 < LEAST_FREE_VID

# End
