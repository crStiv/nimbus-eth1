# Fluffy
# Copyright (c) 2022-2024 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.used.}

import
  unittest2,
  stew/byteutils,
  stew/io2,
  results,
  beacon_chain/networking/network_metadata,
  beacon_chain/spec/forks,
  beacon_chain/spec/datatypes/altair,
  ../../network/beacon/beacon_content,
  ../../eth_data/yaml_utils,
  "."/light_client_test_data

suite "Beacon Content Encodings - Mainnet":
  # These test vectors are generated by eth_data_exporter. The content is taken
  # from mainnet and encoded as it would be transmitted on Portal Network,
  # including also the content key.
  const testVectorDir =
    "./vendor/portal-spec-tests/tests/mainnet/beacon_chain/light_client/"

  let
    metadata = getMetadataForNetwork("mainnet")
    genesisState =
      try:
        template genesisData(): auto =
          metadata.genesis.bakedBytes

        newClone(
          readSszForkedHashedBeaconState(
            metadata.cfg, genesisData.toOpenArray(genesisData.low, genesisData.high)
          )
        )
      except CatchableError as err:
        raiseAssert "Invalid baked-in state: " & err.msg
    genesis_validators_root = getStateField(genesisState[], genesis_validators_root)
    forkDigests = newClone ForkDigests.init(metadata.cfg, genesis_validators_root)

  test "LightClientBootstrap":
    const file = testVectorDir & "bootstrap.yaml"
    let
      c = YamlPortalContent.loadFromYaml(file).valueOr:
        raiseAssert "Invalid test vector file: " & error

      contentKeyEncoded = c.content_key.hexToSeqByte()
      contentValueEncoded = c.content_value.hexToSeqByte()

      # Decode content and content key
      contentKey = decodeSsz(contentKeyEncoded, ContentKey)
      contentValue =
        decodeLightClientBootstrapForked(forkDigests[], contentValueEncoded)
    check:
      contentKey.isOk()
      contentValue.isOk()

    let bootstrap = contentValue.value()
    let key = contentKey.value()

    withForkyObject(bootstrap):
      when lcDataFork > LightClientDataFork.None:
        let blockRoot = hash_tree_root(forkyObject.header.beacon)
        check blockRoot == key.lightClientBootstrapKey.blockHash

    # re-encode content and content key
    let encoded = encodeForkedLightClientObject(bootstrap, forkDigests.capella)

    check encoded == contentValueEncoded
    check encode(key).asSeq() == contentKeyEncoded

  test "LightClientUpdates":
    const file = testVectorDir & "updates.yaml"
    let
      c = YamlPortalContent.loadFromYaml(file).valueOr:
        raiseAssert "Invalid test vector file: " & error

      contentKeyEncoded = c.content_key.hexToSeqByte()
      contentValueEncoded = c.content_value.hexToSeqByte()

      # Decode content and content key
      contentKey = decodeSsz(contentKeyEncoded, ContentKey)
      contentValue = decodeLightClientUpdatesByRange(forkDigests[], contentValueEncoded)
    check:
      contentKey.isOk()
      contentValue.isOk()

    let updates = contentValue.value()
    let key = contentKey.value()

    check key.lightClientUpdateKey.count == uint64(updates.len())

    for i, update in updates:
      withForkyObject(update):
        when lcDataFork > LightClientDataFork.None:
          check forkyObject.finalized_header.beacon.slot div
            (SLOTS_PER_EPOCH * EPOCHS_PER_SYNC_COMMITTEE_PERIOD) ==
            key.lightClientUpdateKey.startPeriod + uint64(i)

    # re-encode content and content key
    let encoded = encodeLightClientUpdatesForked(forkDigests.capella, updates.asSeq())

    check encoded == contentValueEncoded
    check encode(key).asSeq() == contentKeyEncoded

  test "LightClientFinalityUpdate":
    const file = testVectorDir & "finality_update.yaml"
    let
      c = YamlPortalContent.loadFromYaml(file).valueOr:
        raiseAssert "Invalid test vector file: " & error

      contentKeyEncoded = c.content_key.hexToSeqByte()
      contentValueEncoded = c.content_value.hexToSeqByte()

      # Decode content and content key
      contentKey = decodeSsz(contentKeyEncoded, ContentKey)
      contentValue =
        decodeLightClientFinalityUpdateForked(forkDigests[], contentValueEncoded)

    check:
      contentKey.isOk()
      contentValue.isOk()

    let update = contentValue.value()
    let key = contentKey.value()
    withForkyObject(update):
      when lcDataFork > LightClientDataFork.None:
        check forkyObject.finalized_header.beacon.slot ==
          key.lightClientFinalityUpdateKey.finalizedSlot

    # re-encode content and content key
    let encoded = encodeForkedLightClientObject(update, forkDigests.capella)

    check encoded == contentValueEncoded
    check encode(key).asSeq() == contentKeyEncoded

  test "LightClientOptimisticUpdate":
    const file = testVectorDir & "optimistic_update.yaml"
    let
      c = YamlPortalContent.loadFromYaml(file).valueOr:
        raiseAssert "Invalid test vector file: " & error

      contentKeyEncoded = c.content_key.hexToSeqByte()
      contentValueEncoded = c.content_value.hexToSeqByte()

      # Decode content and content key
      contentKey = decodeSsz(contentKeyEncoded, ContentKey)
      contentValue =
        decodeLightClientOptimisticUpdateForked(forkDigests[], contentValueEncoded)

    check:
      contentKey.isOk()
      contentValue.isOk()

    let update = contentValue.value()
    let key = contentKey.value()
    withForkyObject(update):
      when lcDataFork > LightClientDataFork.None:
        check forkyObject.signature_slot ==
          key.lightClientOptimisticUpdateKey.optimisticSlot

    # re-encode content and content key
    let encoded = encodeForkedLightClientObject(update, forkDigests.capella)

    check encoded == contentValueEncoded
    check encode(key).asSeq() == contentKeyEncoded

suite "Beacon Content Encodings":
  # TODO: These tests are less useful now and should instead be altered to
  # use the consensus test vectors to simply test if encoding / decoding works
  # fine for the different forks.
  const forkDigests = ForkDigests(
    phase0: ForkDigest([0'u8, 0, 0, 1]),
    altair: ForkDigest([0'u8, 0, 0, 2]),
    bellatrix: ForkDigest([0'u8, 0, 0, 3]),
    capella: ForkDigest([0'u8, 0, 0, 4]),
    deneb: ForkDigest([0'u8, 0, 0, 5]),
  )

  test "LightClientBootstrap":
    let
      altairData = SSZ.decode(bootstrapBytes, altair.LightClientBootstrap)
      bootstrap = ForkedLightClientBootstrap(
        kind: LightClientDataFork.Altair, altairData: altairData
      )

      encoded = encodeForkedLightClientObject(bootstrap, forkDigests.altair)
      decoded = decodeLightClientBootstrapForked(forkDigests, encoded)

    check:
      decoded.isOk()
      decoded.get().kind == LightClientDataFork.Altair
      decoded.get().altairData == altairData

  test "LightClientUpdate":
    let
      altairData = SSZ.decode(lightClientUpdateBytes, altair.LightClientUpdate)
      update = ForkedLightClientUpdate(
        kind: LightClientDataFork.Altair, altairData: altairData
      )

      encoded = encodeForkedLightClientObject(update, forkDigests.altair)
      decoded = decodeLightClientUpdateForked(forkDigests, encoded)

    check:
      decoded.isOk()
      decoded.get().kind == LightClientDataFork.Altair
      decoded.get().altairData == altairData

  test "LightClientUpdateList":
    let
      altairData = SSZ.decode(lightClientUpdateBytes, altair.LightClientUpdate)
      update = ForkedLightClientUpdate(
        kind: LightClientDataFork.Altair, altairData: altairData
      )
      updateList = @[update, update]

      encoded = encodeLightClientUpdatesForked(forkDigests.altair, updateList)
      decoded = decodeLightClientUpdatesByRange(forkDigests, encoded)

    check:
      decoded.isOk()
      decoded.get().asSeq()[0].altairData == updateList[0].altairData
      decoded.get().asSeq()[1].altairData == updateList[1].altairData

  test "LightClientFinalityUpdate":
    let
      altairData =
        SSZ.decode(lightClientFinalityUpdateBytes, altair.LightClientFinalityUpdate)
      update = ForkedLightClientFinalityUpdate(
        kind: LightClientDataFork.Altair, altairData: altairData
      )

      encoded = encodeForkedLightClientObject(update, forkDigests.altair)
      decoded = decodeLightClientFinalityUpdateForked(forkDigests, encoded)

    check:
      decoded.isOk()
      decoded.get().kind == LightClientDataFork.Altair
      decoded.get().altairData == altairData

  test "LightClientOptimisticUpdate":
    let
      altairData =
        SSZ.decode(lightClientOptimisticUpdateBytes, altair.LightClientOptimisticUpdate)
      update = ForkedLightClientOptimisticUpdate(
        kind: LightClientDataFork.Altair, altairData: altairData
      )

      encoded = encodeForkedLightClientObject(update, forkDigests.altair)
      decoded = decodeLightClientOptimisticUpdateForked(forkDigests, encoded)

    check:
      decoded.isOk()
      decoded.get().kind == LightClientDataFork.Altair
      decoded.get().altairData == altairData

  test "Invalid LightClientBootstrap":
    let
      altairData = SSZ.decode(bootstrapBytes, altair.LightClientBootstrap)
      # TODO: This doesn't make much sense with current API
      bootstrap = ForkedLightClientBootstrap(
        kind: LightClientDataFork.Altair, altairData: altairData
      )

      encodedTooEarlyFork = encodeForkedLightClientObject(bootstrap, forkDigests.phase0)
      encodedUnknownFork =
        encodeForkedLightClientObject(bootstrap, ForkDigest([0'u8, 0, 0, 6]))

    check:
      decodeLightClientBootstrapForked(forkDigests, @[]).isErr()
      decodeLightClientBootstrapForked(forkDigests, encodedTooEarlyFork).isErr()
      decodeLightClientBootstrapForked(forkDigests, encodedUnknownFork).isErr()

suite "Beacon ContentKey Encodings ":
  test "Invalid prefix - 0 value":
    let encoded = ByteList.init(@[byte 0x00])
    let decoded = decode(encoded)

    check decoded.isNone()

  test "Invalid prefix - before valid range":
    let encoded = ByteList.init(@[byte 0x01])
    let decoded = decode(encoded)

    check decoded.isNone()

  test "Invalid prefix - after valid range":
    let encoded = ByteList.init(@[byte 0x14])
    let decoded = decode(encoded)

    check decoded.isNone()

  test "Invalid key - empty input":
    let encoded = ByteList.init(@[])
    let decoded = decode(encoded)

    check decoded.isNone()
