proc eth_getBlockByHash(data: EthHashStr, fullTransactions: bool): Option[BlockObject]
proc eth_getLogs(filterOptions: FilterOptions): seq[FilterLog]
