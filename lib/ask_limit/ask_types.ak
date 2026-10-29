use aiken/crypto.{VerificationKeyHash}
use cardano/address.{Address}
use cardano/assets.{PolicyId}
use daken/types.{Basis, TupleAsset} as daken_types

// Datum of a sell order. No NFT is minted, so the order is identified by its
// out_ref. owner_vk is a payment key hash: v1 does not support script wallets,
// and off-chain has to refuse them.
pub type AskDatum {
  owner_vk: VerificationKeyHash,
  requested_yield: Basis,
}

// Config UTxO, held at the nft_license address. Only whoever holds the
// license NFT can change it.
pub type ExchangeConfig {
  fee_addr: Address,
  buyer_fee: Basis,
  seller_fee: Basis,
  // Pool policy ids, one per deployment generation — not a list of pools.
  pt_policies: List<PolicyId>,
}

// Compile-time parameter of the validator.
pub type AskLimitConfig {
  config_nft: TupleAsset,
}

pub type AskLimitAction {
  indexers: AskIndexer,
  order_in_idx: Int,
  config_ref_idx: Int,
  fee_ou_idx: Int,
}

pub type AskIndexer {
  // Update(cont_ou_idx); a cont_ou_idx below zero cancels the order.
  Update(Int)
  // Redeemer of the spend branch when an order is filled. It carries no fill
  // list: the spend branch reads the list from the withdraw redeemer instead.
  // Carrying it would repeat the list N+1 times in one transaction, and both
  // bytes and CPU would grow as N².
  Buy
  // Redeemer of the withdraw branch. BuyMulti(List<(pool_ref_idx, List<Fill>)>)
  BuyMulti(List<PoolFills>)
}

// Fills grouped by pool, so each PoolDatum is read once per pool.
pub type PoolFills =
  (Int, List<Fill>)

pub type Fill {
  order_in_idx: Int,
  owner_ou_idx: Int,
  // Below zero means the order was bought out, leaving no remainder.
  cont_ou_idx: Int,
}
