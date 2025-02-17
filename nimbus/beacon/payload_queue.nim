# Nimbus
# Copyright (c) 2022-2024 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  eth/common/[headers, hashes],
  web3/engine_api_types,
  web3/execution_types

const
  # maxTrackedPayloads is the maximum number of prepared payloads the execution
  # engine tracks before evicting old ones. Ideally we should only ever track
  # the latest one; but have a slight wiggle room for non-ideal conditions.
  MaxTrackedPayloads = 10

  # maxTrackedHeaders is the maximum number of executed payloads the execution
  # engine tracks before evicting old ones. Ideally we should only ever track
  # the latest one; but have a slight wiggle room for non-ideal conditions.
  MaxTrackedHeaders = 96

type
  QueueItem[T] = object
    used: bool
    data: T

  SimpleQueue[M: static[int]; T] = object
    list: array[M, QueueItem[T]]

  ExecutionBundle* = object
    payload*: ExecutionPayload
    blockValue*: UInt256
    blobsBundle*: Opt[BlobsBundleV1]
    executionRequests*: Opt[array[3, seq[byte]]]
    targetBlobsPerBlock*: Opt[Quantity]

  PayloadItem = object
    id: Bytes8
    payload: ExecutionBundle

  HeaderItem = object
    hash: Hash32
    header: Header

  PayloadQueue* = object
    payloadQueue: SimpleQueue[MaxTrackedPayloads, PayloadItem]
    headerQueue: SimpleQueue[MaxTrackedHeaders, HeaderItem]

{.push gcsafe, raises:[].}

# ------------------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------------------

template shiftRight[M, T](x: var SimpleQueue[M, T]) =
  x.list[1..^1] = x.list[0..^2]

proc put[M, T](x: var SimpleQueue[M, T], val: T) =
  x.shiftRight()
  x.list[0] = QueueItem[T](used: true, data: val)

iterator items[M, T](x: SimpleQueue[M, T]): T =
  for z in x.list:
    if z.used:
      yield z.data

# ------------------------------------------------------------------------------
# Public functions, setters
# ------------------------------------------------------------------------------

proc put*(api: var PayloadQueue,
          hash: Hash32, header: Header) =
  api.headerQueue.put(HeaderItem(hash: hash, header: header))

proc put*(api: var PayloadQueue, id: Bytes8,
          payload: ExecutionBundle) =
  api.payloadQueue.put(PayloadItem(id: id, payload: payload))

# ------------------------------------------------------------------------------
# Public functions, getters
# ------------------------------------------------------------------------------

proc get*(api: PayloadQueue, hash: Hash32,
          header: var Header): bool =
  for x in api.headerQueue:
    if x.hash == hash:
      header = x.header
      return true
  false

proc get*(api: PayloadQueue, id: Bytes8,
          payload: var ExecutionBundle): bool =
  for x in api.payloadQueue:
    if x.id == id:
      payload = x.payload
      return true
  false
