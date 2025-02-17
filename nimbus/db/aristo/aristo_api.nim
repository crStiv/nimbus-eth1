# nimbus-eth1
# Copyright (c) 2024 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
#    http://www.apache.org/licenses/LICENSE-2.0)
#  * MIT license ([LICENSE-MIT](LICENSE-MIT) or
#    http://opensource.org/licenses/MIT)
# at your option. This file may not be copied, modified, or distributed
# except according to those terms.

## Stackable API for `Aristo`
## ==========================


import
  std/times,
  eth/common,
  results,
  ./aristo_desc/desc_backend,
  ./aristo_init/memory_db,
  "."/[aristo_delete, aristo_desc, aristo_fetch, aristo_init, aristo_merge,
       aristo_part, aristo_path, aristo_profile, aristo_tx]

export
  AristoDbProfListRef

const
  AutoValidateApiHooks = defined(release).not
    ## No validatinon needed for production suite.

  AristoPersistentBackendOk = AutoValidateApiHooks # and false
    ## Set true for persistent backend profiling (which needs an extra
    ## link library.)

when AristoPersistentBackendOk:
  import ./aristo_init/rocks_db

# Annotation helper(s)
{.pragma: noRaise, gcsafe, raises: [].}

type
  AristoApiCommitFn* =
    proc(tx: AristoTxRef;
        ): Result[void,AristoError]
        {.noRaise.}
      ## Given a *top level* handle, this function accepts all database
      ## operations performed through this handle and merges it to the
      ## previous layer. The previous transaction is returned if there
      ## was any.

  AristoApiDeleteAccountRecordFn* =
    proc(db: AristoDbRef;
         accPath: Hash32;
        ): Result[void,AristoError]
        {.noRaise.}
      ## Delete the account leaf entry addressed by the argument `path`. If
      ## this leaf entry referres to a storage tree, this one will be deleted
      ## as well.

  AristoApiDeleteStorageDataFn* =
    proc(db: AristoDbRef;
         accPath: Hash32;
         stoPath: Hash32;
        ): Result[bool,AristoError]
        {.noRaise.}
      ## For a given account argument `accPath`, this function deletes the
      ## argument `stoPath` from the associated storage tree (if any, at all.)
      ## If the if the argument `stoPath` deleted was the last one on the
      ## storage tree, account leaf referred to by `accPath` will be updated
      ## so that it will not refer to a storage tree anymore. In the latter
      ## case only the function will return `true`.

  AristoApiDeleteStorageTreeFn* =
    proc(db: AristoDbRef;
         accPath: Hash32;
        ): Result[void,AristoError]
        {.noRaise.}
      ## Variant of `deleteStorageData()` for purging the whole storage tree
      ## associated to the account argument `accPath`.

  AristoApiFetchLastSavedStateFn* =
    proc(db: AristoDbRef
        ): Result[SavedState,AristoError]
        {.noRaise.}
      ## The function returns the state of the last saved state. This is a
      ## Merkle hash tag for vertex with ID 1 and a bespoke `uint64` identifier
      ## (may be interpreted as block number.)

  AristoApiFetchAccountRecordFn* =
    proc(db: AristoDbRef;
         accPath: Hash32;
        ): Result[AristoAccount,AristoError]
        {.noRaise.}
      ## Fetch an account record from the database indexed by `accPath`.

  AristoApiFetchStateRootFn* =
    proc(db: AristoDbRef;
        ): Result[Hash32,AristoError]
        {.noRaise.}
      ## Fetch the Merkle hash of the account root.

  AristoApiFetchStorageDataFn* =
    proc(db: AristoDbRef;
         accPath: Hash32;
         stoPath: Hash32;
        ): Result[UInt256,AristoError]
        {.noRaise.}
      ## For a storage tree related to account `accPath`, fetch the data
      ## record from the database indexed by `stoPath`.

  AristoApiFetchStorageRootFn* =
    proc(db: AristoDbRef;
         accPath: Hash32;
        ): Result[Hash32,AristoError]
        {.noRaise.}
      ## Fetch the Merkle hash of the storage root related to `accPath`.

  AristoApiFinishFn* =
    proc(db: AristoDbRef;
         eradicate = false;
        ) {.noRaise.}
      ## Backend destructor. The argument `eradicate` indicates that a full
      ## database deletion is requested. If set `false` the outcome might
      ## differ depending on the type of backend (e.g. the `BackendMemory`
      ## backend will always eradicate on close.)
      ##
      ## In case of distributed descriptors accessing the same backend, all
      ## distributed descriptors will be destroyed.
      ##
      ## This distructor may be used on already *destructed* descriptors.

  AristoApiForgetFn* =
    proc(db: AristoDbRef;
        ): Result[void,AristoError]
        {.noRaise.}
      ## Destruct the non centre argument `db` descriptor (see comments on
      ## `reCentre()` for details.)
      ##
      ## A non centre descriptor should always be destructed after use (see
      ## also# comments on `fork()`.)

  AristoApiHashifyFn* =
    proc(db: AristoDbRef;
        ): Result[void,(VertexID,AristoError)]
        {.noRaise.}
      ## Add keys to the  `Patricia Trie` so that it becomes a `Merkle
      ## Patricia Tree`.

  AristoApiHasPathAccountFn* =
    proc(db: AristoDbRef;
         accPath: Hash32;
        ): Result[bool,AristoError]
        {.noRaise.}
      ## For an account record indexed by `accPath` query whether this record
      ## exists on the database.

  AristoApiHasPathStorageFn* =
    proc(db: AristoDbRef;
         accPath: Hash32;
         stoPath: Hash32;
        ): Result[bool,AristoError]
        {.noRaise.}
      ## For a storage tree related to account `accPath`, query whether the
      ## data record indexed by `stoPath` exists on the database.

  AristoApiHasStorageDataFn* =
    proc(db: AristoDbRef;
         accPath: Hash32;
        ): Result[bool,AristoError]
        {.noRaise.}
      ## For a storage tree related to account `accPath`, query whether there
      ## is a non-empty data storage area at all.

  AristoApiIsTopFn* =
    proc(tx: AristoTxRef;
        ): bool
        {.noRaise.}
      ## Getter, returns `true` if the argument `tx` referes to the current
      ## top level transaction.

  AristoApiTxFrameLevelFn* =
    proc(db: AristoDbRef;
        ): int
        {.noRaise.}
      ## Getter, non-negative nesting level (i.e. number of pending
      ## transactions)

  AristoApiMergeAccountRecordFn* =
    proc(db: AristoDbRef;
         accPath: Hash32;
         accRec: AristoAccount;
        ): Result[bool,AristoError]
        {.noRaise.}
      ## Merge the  key-value-pair argument `(accKey,accRec)` as an account
      ## ledger value, i.e. the the sub-tree starting at `VertexID(1)`.
      ##
      ## On success, the function returns `true` if the `accPath` argument was
      ## not on the database already or the value differend from `accRec`, and
      ## `false` otherwise.

  AristoApiMergeStorageDataFn* =
    proc(db: AristoDbRef;
         accPath: Hash32;
         stoPath: Hash32;
         stoData: UInt256;
        ): Result[void,AristoError]
        {.noRaise.}
      ## Store the `stoData` data argument on the storage area addressed by
      ## `(accPath,stoPath)` where `accPath` is the account key (into the MPT)
      ## and `stoPath`  is the slot path of the corresponding storage area.

  AristoApiPartAccountTwig* =
    proc(db: AristoDbRef;
         accPath: Hash32;
        ): Result[(seq[seq[byte]],bool), AristoError]
        {.noRaise.}
      ## This function returns a chain of rlp-encoded nodes along the argument
      ## path `(root,path)` followed by a `true` value if the `path` argument
      ## exists in the database. If the argument `path` is not on the database,
      ## a partial path will be returned follwed by a `false` value.
      ##
      ## Errors will only be returned for invalid paths.

  AristoApiPartStorageTwig* =
    proc(db: AristoDbRef;
         accPath: Hash32;
         stoPath: Hash32;
        ): Result[(seq[seq[byte]],bool), AristoError]
        {.noRaise.}
      ## Variant of `partAccountTwig()`. Note that the function always returns
      ## an error unless the `accPath` is valid.

  AristoApiPartUntwigGeneric* =
    proc(chain: openArray[seq[byte]];
         root: Hash32;
         path: openArray[byte];
        ): Result[Opt[seq[byte]],AristoError]
        {.noRaise.}
      ## Follow and verify the argument `chain` up unlil the last entry which
      ## must be a leaf node. Extract the payload and pass it on as return
      ## code. If a `Opt.none()` result is returned then the `path` argument
      ## does provably not exist relative to `chain`.

  AristoApiPartUntwigGenericOk* =
    proc(chain: openArray[seq[byte]];
         root: Hash32;
         path: openArray[byte];
         payload: Opt[seq[byte]];
        ): Result[void,AristoError]
        {.noRaise.}
      ## Variant of `partUntwigGeneric()`. The function verifies the argument
      ## `chain` of rlp-encoded nodes against the `path` and `payload`
      ## arguments. If `payload` is passed `Opt.none()`, then the function is
      ## subject to proving that the `path` does not exist relaive to `chain`.
      ##
      ## Note: This function provides a functionality comparable to the
      ## `isValidBranch()` function from `hexary.nim`.

  AristoApiPartUntwigPath* =
    proc(chain: openArray[seq[byte]];
         root: Hash32;
         path: Hash32;
        ): Result[Opt[seq[byte]],AristoError]
        {.noRaise.}
      ## Variant of `partUntwigGeneric()`.

  AristoApiPartUntwigPathOk* =
    proc(chain: openArray[seq[byte]];
         root: Hash32;
         path: Hash32;
         payload: Opt[seq[byte]];
        ): Result[void,AristoError]
        {.noRaise.}
      ## Variant of `partUntwigGenericOk()`.

  AristoApiPathAsBlobFn* =
    proc(tag: PathID;
        ): seq[byte]
        {.noRaise.}
      ## Converts the `tag` argument to a sequence of an even number of
      ## nibbles represented by a `seq[byte]`. If the argument `tag` represents
      ## an odd number of nibbles, a zero nibble is appendend.
      ##
      ## This function is useful only if there is a tacit agreement that all
      ## paths used to index database leaf values can be represented as
      ## `seq[byte]`, i.e. `PathID` type paths with an even number of nibbles.

  AristoApiPersistFn* =
    proc(db: AristoDbRef;
         nxtSid = 0u64;
        ): Result[void,AristoError]
        {.noRaise.}
      ## Persistently store data onto backend database. If the system is
      ## running without a database backend, the function returns immediately
      ## with an error. The same happens if there is a pending transaction.
      ##
      ## The function merges all staged data from the top layer cache onto the
      ## backend stage area. After that, the top layer cache is cleared.
      ##
      ## Finally, the staged data are merged into the physical backend
      ## database and the staged data area is cleared.
      ##
      ## The argument `nxtSid` will be the ID for the next saved state record.

  AristoApiRollbackFn* =
    proc(tx: AristoTxRef;
        ): Result[void,AristoError]
        {.noRaise.}
      ## Given a *top level* handle, this function discards all database
      ## operations performed for this transactio. The previous transaction
      ## is returned if there was any.

  AristoApiTxFrameBeginFn* =
    proc(db: AristoDbRef;
        ): Result[AristoTxRef,AristoError]
        {.noRaise.}
      ## Starts a new transaction.
      ##
      ## Example:
      ## ::
      ##   proc doSomething(db: AristoDbRef) =
      ##     let tx = db.begin
      ##     defer: tx.rollback()
      ##     ... continue using db ...
      ##     tx.commit()

  AristoApiTxFrameTopFn* =
    proc(db: AristoDbRef;
        ): Result[AristoTxRef,AristoError]
        {.noRaise.}
      ## Getter, returns top level transaction if there is any.

  AristoApiRef* = ref AristoApiObj
  AristoApiObj* = object of RootObj
    ## Useful set of `Aristo` fuctions that can be filtered, stacked etc.
    commit*: AristoApiCommitFn

    deleteAccountRecord*: AristoApiDeleteAccountRecordFn
    deleteStorageData*: AristoApiDeleteStorageDataFn
    deleteStorageTree*: AristoApiDeleteStorageTreeFn

    fetchLastSavedState*: AristoApiFetchLastSavedStateFn

    fetchAccountRecord*: AristoApiFetchAccountRecordFn
    fetchStateRoot*: AristoApiFetchStateRootFn
    fetchStorageData*: AristoApiFetchStorageDataFn
    fetchStorageRoot*: AristoApiFetchStorageRootFn

    finish*: AristoApiFinishFn
    hasPathAccount*: AristoApiHasPathAccountFn
    hasPathStorage*: AristoApiHasPathStorageFn
    hasStorageData*: AristoApiHasStorageDataFn

    isTop*: AristoApiIsTopFn
    txFrameLevel*: AristoApiTxFrameLevelFn

    mergeAccountRecord*: AristoApiMergeAccountRecordFn
    mergeStorageData*: AristoApiMergeStorageDataFn

    partAccountTwig*: AristoApiPartAccountTwig
    partStorageTwig*: AristoApiPartStorageTwig
    partUntwigGeneric*: AristoApiPartUntwigGeneric
    partUntwigGenericOk*: AristoApiPartUntwigGenericOk
    partUntwigPath*: AristoApiPartUntwigPath
    partUntwigPathOk*: AristoApiPartUntwigPathOk

    pathAsBlob*: AristoApiPathAsBlobFn
    persist*: AristoApiPersistFn
    rollback*: AristoApiRollbackFn
    txFrameBegin*: AristoApiTxFrameBeginFn
    txFrameTop*: AristoApiTxFrameTopFn


  AristoApiProfNames* = enum
    ## Index/name mapping for profile slots
    AristoApiProfTotal                  = "total"
    AristoApiProfCommitFn               = "commit"

    AristoApiProfDeleteAccountRecordFn  = "deleteAccountRecord"
    AristoApiProfDeleteStorageDataFn    = "deleteStorageData"
    AristoApiProfDeleteStorageTreeFn    = "deleteStorageTree"

    AristoApiProfFetchLastSavedStateFn  = "fetchLastSavedState"

    AristoApiProfFetchAccountRecordFn   = "fetchAccountRecord"
    AristoApiProfFetchStateRootFn = "fetchStateRoot"
    AristoApiProfFetchStorageDataFn     = "fetchStorageData"
    AristoApiProfFetchStorageRootFn     = "fetchStorageRoot"

    AristoApiProfFinishFn               = "finish"

    AristoApiProfHasPathAccountFn       = "hasPathAccount"
    AristoApiProfHasPathStorageFn       = "hasPathStorage"
    AristoApiProfHasStorageDataFn       = "hasStorageData"

    AristoApiProfIsTopFn                = "isTop"
    AristoApiProfLevelFn                = "level"

    AristoApiProfMergeAccountRecordFn   = "mergeAccountRecord"
    AristoApiProfMergeStorageDataFn     = "mergeStorageData"

    AristoApiProfPartAccountTwigFn      = "partAccountTwig"
    AristoApiProfPartStorageTwigFn      = "partStorageTwig"
    AristoApiProfPartUntwigPathFn       = "partUntwigPath"
    AristoApiProfPartUntwigPathOkFn     = "partUntwigPathOk"

    AristoApiProfPathAsBlobFn           = "pathAsBlob"
    AristoApiProfPersistFn              = "persist"
    AristoApiProfRollbackFn             = "rollback"
    AristoApiProfTxFrameBeginFn              = "txFrameBegin"
    AristoApiProfTxFrameTopFn                = "txFrameTop"

    AristoApiProfBeGetVtxFn             = "be/getVtx"
    AristoApiProfBeGetKeyFn             = "be/getKey"
    AristoApiProfBeGetTuvFn             = "be/getTuv"
    AristoApiProfBeGetLstFn             = "be/getLst"
    AristoApiProfBePutVtxFn             = "be/putVtx"
    AristoApiProfBePutTuvFn             = "be/putTuv"
    AristoApiProfBePutLstFn             = "be/putLst"
    AristoApiProfBePutEndFn             = "be/putEnd"

  AristoApiProfRef* = ref object of AristoApiRef
    ## Profiling API extension of `AristoApiObj`
    data*: AristoDbProfListRef
    be*: BackendRef

# ------------------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------------------

when AutoValidateApiHooks:
  proc validate(api: AristoApiObj|AristoApiRef) =
    doAssert not api.commit.isNil

    doAssert not api.deleteAccountRecord.isNil
    doAssert not api.deleteStorageData.isNil
    doAssert not api.deleteStorageTree.isNil

    doAssert not api.fetchLastSavedState.isNil

    doAssert not api.fetchAccountRecord.isNil
    doAssert not api.fetchStateRoot.isNil
    doAssert not api.fetchStorageData.isNil
    doAssert not api.fetchStorageRoot.isNil

    doAssert not api.finish.isNil

    doAssert not api.hasPathAccount.isNil
    doAssert not api.hasPathStorage.isNil
    doAssert not api.hasStorageData.isNil

    doAssert not api.isTop.isNil
    doAssert not api.txFrameLevel.isNil

    doAssert not api.mergeAccountRecord.isNil
    doAssert not api.mergeStorageData.isNil

    doAssert not api.partAccountTwig.isNil
    doAssert not api.partStorageTwig.isNil
    doAssert not api.partUntwigPath.isNil
    doAssert not api.partUntwigPathOk.isNil

    doAssert not api.pathAsBlob.isNil
    doAssert not api.persist.isNil
    doAssert not api.rollback.isNil
    doAssert not api.txFrameBegin.isNil
    doAssert not api.txFrameTop.isNil

  proc validate(prf: AristoApiProfRef) =
    prf.AristoApiRef.validate
    doAssert not prf.data.isNil

proc dup(be: BackendRef): BackendRef =
  case be.kind:
  of BackendMemory:
    return MemBackendRef(be).dup

  of BackendRocksDB, BackendRdbHosting:
    when AristoPersistentBackendOk:
      return RdbBackendRef(be).dup

  of BackendVoid:
    discard

# ------------------------------------------------------------------------------
# Public API constuctors
# ------------------------------------------------------------------------------

func init*(api: var AristoApiObj) =
  ## Initialise an `api` argument descriptor
  ##
  when AutoValidateApiHooks:
    api.reset
  api.commit = commit

  api.deleteAccountRecord = deleteAccountRecord
  api.deleteStorageData = deleteStorageData
  api.deleteStorageTree = deleteStorageTree

  api.fetchLastSavedState = fetchLastSavedState

  api.fetchAccountRecord = fetchAccountRecord
  api.fetchStateRoot = fetchStateRoot
  api.fetchStorageData = fetchStorageData
  api.fetchStorageRoot = fetchStorageRoot

  api.finish = finish

  api.hasPathAccount = hasPathAccount
  api.hasPathStorage = hasPathStorage
  api.hasStorageData = hasStorageData

  api.isTop = isTop
  api.txFrameLevel = txFrameLevel

  api.mergeAccountRecord = mergeAccountRecord
  api.mergeStorageData = mergeStorageData

  api.partAccountTwig = partAccountTwig
  api.partStorageTwig = partStorageTwig
  api.partUntwigPath = partUntwigPath
  api.partUntwigPathOk = partUntwigPathOk

  api.pathAsBlob = pathAsBlob
  api.persist = persist
  api.rollback = rollback
  api.txFrameBegin = txFrameBegin
  api.txFrameTop = txFrameTop
  when AutoValidateApiHooks:
    api.validate

func init*(T: type AristoApiRef): T =
  new result
  result[].init()

func dup*(api: AristoApiRef): AristoApiRef =
  result = AristoApiRef(
    commit:               api.commit,

    deleteAccountRecord:  api.deleteAccountRecord,
    deleteStorageData:    api.deleteStorageData,
    deleteStorageTree:    api.deleteStorageTree,

    fetchLastSavedState:  api.fetchLastSavedState,
    fetchAccountRecord:   api.fetchAccountRecord,
    fetchStateRoot: api.fetchStateRoot,
    fetchStorageData:     api.fetchStorageData,
    fetchStorageRoot:     api.fetchStorageRoot,

    finish:               api.finish,

    hasPathAccount:       api.hasPathAccount,
    hasPathStorage:       api.hasPathStorage,
    hasStorageData:       api.hasStorageData,

    isTop:                api.isTop,
    txFrameLevel:              api.txFrameLevel,

    mergeAccountRecord:   api.mergeAccountRecord,
    mergeStorageData:     api.mergeStorageData,

    partAccountTwig:      api.partAccountTwig,
    partStorageTwig:      api.partStorageTwig,
    partUntwigPath:       api.partUntwigPath,
    partUntwigPathOk:     api.partUntwigPathOk,

    pathAsBlob:           api.pathAsBlob,
    persist:              api.persist,
    rollback:             api.rollback,
    txFrameBegin:              api.txFrameBegin,
    txFrameTop:                api.txFrameTop)
  when AutoValidateApiHooks:
    result.validate

# ------------------------------------------------------------------------------
# Public profile API constuctor
# ------------------------------------------------------------------------------

func init*(
    T: type AristoApiProfRef;
    api: AristoApiRef;
    be = BackendRef(nil);
      ): T =
  ## This constructor creates a profiling API descriptor to be derived from
  ## an initialised `api` argument descriptor. For profiling the DB backend,
  ## the field `.be` of the result descriptor must be assigned to the
  ## `.backend` field of the `AristoDbRef` descriptor.
  ##
  ## The argument desctiptors `api` and `be` will not be modified and can be
  ## used to restore the previous set up.
  ##
  let
    data = AristoDbProfListRef(
      list: newSeq[AristoDbProfData](1 + high(AristoApiProfNames).ord))
    profApi = T(data: data)

  template profileRunner(n: AristoApiProfNames, code: untyped): untyped =
    let start = getTime()
    code
    data.update(n.ord, getTime() - start)

  profApi.commit =
    proc(a: AristoTxRef): auto =
      AristoApiProfCommitFn.profileRunner:
        result = api.commit(a)

  profApi.deleteAccountRecord =
    proc(a: AristoDbRef; b: Hash32): auto =
      AristoApiProfDeleteAccountRecordFn.profileRunner:
        result = api.deleteAccountRecord(a, b)

  profApi.deleteStorageData =
    proc(a: AristoDbRef; b: Hash32, c: Hash32): auto =
      AristoApiProfDeleteStorageDataFn.profileRunner:
        result = api.deleteStorageData(a, b, c)

  profApi.deleteStorageTree =
    proc(a: AristoDbRef; b: Hash32): auto =
      AristoApiProfDeleteStorageTreeFn.profileRunner:
        result = api.deleteStorageTree(a, b)

  profApi.fetchLastSavedState =
    proc(a: AristoDbRef): auto =
      AristoApiProfFetchLastSavedStateFn.profileRunner:
        result = api.fetchLastSavedState(a)

  profApi.fetchAccountRecord =
    proc(a: AristoDbRef; b: Hash32): auto =
      AristoApiProfFetchAccountRecordFn.profileRunner:
        result = api.fetchAccountRecord(a, b)

  profApi.fetchStateRoot =
    proc(a: AristoDbRef; b: bool): auto =
      AristoApiProfFetchStateRootFn.profileRunner:
        result = api.fetchStateRoot(a, b)

  profApi.fetchStorageData =
    proc(a: AristoDbRef; b, stoPath: Hash32): auto =
      AristoApiProfFetchStorageDataFn.profileRunner:
        result = api.fetchStorageData(a, b, stoPath)

  profApi.fetchStorageRoot =
    proc(a: AristoDbRef; b: Hash32): auto =
      AristoApiProfFetchStorageRootFn.profileRunner:
        result = api.fetchStorageRoot(a, b)

  profApi.finish =
    proc(a: AristoDbRef; b = false) =
      AristoApiProfFinishFn.profileRunner:
        api.finish(a, b)

  profApi.hasPathAccount =
    proc(a: AristoDbRef; b: Hash32): auto =
      AristoApiProfHasPathAccountFn.profileRunner:
        result = api.hasPathAccount(a, b)

  profApi.hasPathStorage =
    proc(a: AristoDbRef; b, c: Hash32): auto =
      AristoApiProfHasPathStorageFn.profileRunner:
        result = api.hasPathStorage(a, b, c)

  profApi.hasStorageData =
    proc(a: AristoDbRef; b: Hash32): auto =
      AristoApiProfHasStorageDataFn.profileRunner:
        result = api.hasStorageData(a, b)

  profApi.isTop =
    proc(a: AristoTxRef): auto =
      AristoApiProfIsTopFn.profileRunner:
        result = api.isTop(a)

  profApi.level =
    proc(a: AristoDbRef): auto =
       AristoApiProfLevelFn.profileRunner:
         result = api.level(a)

  profApi.mergeAccountRecord =
    proc(a: AristoDbRef; b: Hash32; c: AristoAccount): auto =
      AristoApiProfMergeAccountRecordFn.profileRunner:
        result = api.mergeAccountRecord(a, b, c)

  profApi.mergeStorageData =
    proc(a: AristoDbRef; b, c: Hash32, d: UInt256): auto =
      AristoApiProfMergeStorageDataFn.profileRunner:
        result = api.mergeStorageData(a, b, c, d)

  profApi.partAccountTwig =
    proc(a: AristoDbRef; b: Hash32): auto =
      AristoApiProfPartAccountTwigFn.profileRunner:
        result = api.partAccountTwig(a, b)

  profApi.partStorageTwig =
    proc(a: AristoDbRef; b: Hash32; c: Hash32): auto =
      AristoApiProfPartStorageTwigFn.profileRunner:
        result = api.partStorageTwig(a, b, c)

  profApi.partUntwigPath =
    proc(a: openArray[seq[byte]]; b, c: Hash32): auto =
      AristoApiProfPartUntwigPathFn.profileRunner:
        result = api.partUntwigPath(a, b, c)

  profApi.partUntwigPathOk =
    proc(a: openArray[seq[byte]]; b, c: Hash32; d: Opt[seq[byte]]): auto =
      AristoApiProfPartUntwigPathOkFn.profileRunner:
        result = api.partUntwigPathOk(a, b, c, d)

  profApi.pathAsBlob =
    proc(a: PathID): auto =
      AristoApiProfPathAsBlobFn.profileRunner:
        result = api.pathAsBlob(a)

  profApi.persist =
    proc(a: AristoDbRef; b = 0u64): auto =
       AristoApiProfPersistFn.profileRunner:
        result = api.persist(a, b)

  profApi.rollback =
    proc(a: AristoTxRef): auto =
      AristoApiProfRollbackFn.profileRunner:
        result = api.rollback(a)

  profApi.txFrameBegin =
    proc(a: AristoDbRef): auto =
       AristoApiProfTxFrameBeginFn.profileRunner:
        result = api.txFrameBegin(a)

  profApi.txFrameTop =
    proc(a: AristoDbRef): auto =
      AristoApiProfTxFrameTopFn.profileRunner:
        result = api.txFrameTop(a)

  let beDup = be.dup()
  if beDup.isNil:
    profApi.be = be

  else:
    beDup.getVtxFn =
      proc(a: RootedVertexID, flags: set[GetVtxFlag]): auto =
        AristoApiProfBeGetVtxFn.profileRunner:
          result = be.getVtxFn(a, flags)
    data.list[AristoApiProfBeGetVtxFn.ord].masked = true

    beDup.getKeyFn =
      proc(a: RootedVertexID): auto =
        AristoApiProfBeGetKeyFn.profileRunner:
          result = be.getKeyFn(a)
    data.list[AristoApiProfBeGetKeyFn.ord].masked = true

    beDup.getTuvFn =
      proc(): auto =
        AristoApiProfBeGetTuvFn.profileRunner:
          result = be.getTuvFn()
    data.list[AristoApiProfBeGetTuvFn.ord].masked = true

    beDup.getLstFn =
      proc(): auto =
        AristoApiProfBeGetLstFn.profileRunner:
          result = be.getLstFn()
    data.list[AristoApiProfBeGetLstFn.ord].masked = true

    beDup.putVtxFn =
      proc(a: PutHdlRef; b: RootedVertexID, c: VertexRef) =
        AristoApiProfBePutVtxFn.profileRunner:
          be.putVtxFn(a, b, c)
    data.list[AristoApiProfBePutVtxFn.ord].masked = true

    beDup.putTuvFn =
      proc(a: PutHdlRef; b: VertexID) =
        AristoApiProfBePutTuvFn.profileRunner:
          be.putTuvFn(a,b)
    data.list[AristoApiProfBePutTuvFn.ord].masked = true

    beDup.putLstFn =
      proc(a: PutHdlRef; b: SavedState) =
        AristoApiProfBePutLstFn.profileRunner:
          be.putLstFn(a,b)
    data.list[AristoApiProfBePutLstFn.ord].masked = true

    beDup.putEndFn =
      proc(a: PutHdlRef): auto =
        AristoApiProfBePutEndFn.profileRunner:
          result = be.putEndFn(a)
    data.list[AristoApiProfBePutEndFn.ord].masked = true

    profApi.be = beDup

  when AutoValidateApiHooks:
    profApi.validate

  profApi

# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------
