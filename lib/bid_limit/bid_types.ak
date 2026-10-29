use aiken/crypto.{VerificationKeyHash}
use daken/types.{Basis, TupleAsset} as daken_types

// Datum of a buy order. No NFT is minted, so the order is identified by its
// out_ref.
//
// `bid_amount` lives in the datum rather than being derived from the value:
// when the origin token is ADA, the money backing the order and the min-UTxO
// share one `lovelace` field and the value alone cannot separate them. Whatever
// exceeds `bid_amount` is reserve, and it must go back to the order's owner
// when the order closes.
//
// `pt_asset` is required because the order holds money only, and money does not
// say which PT it wants to buy. The policy id is pinned too, so when a pool
// moves to a new generation the old orders stay in the old market.
pub type BidDatum {
  owner_vk: VerificationKeyHash,
  pt_asset: TupleAsset,
  offered_yield: Basis,
  bid_amount: Int,
}

// Compile-time parameter of the validator.
pub type BidLimitConfig {
  config_nft: TupleAsset,
}

pub type BidLimitAction {
  indexers: BidIndexer,
  order_in_idx: Int,
  config_ref_idx: Int,
  fee_ou_idx: Int,
}

pub type BidIndexer {
  // Update(cont_ou_idx); a cont_ou_idx below zero cancels the order.
  Update(Int)
  // Redeemer of the spend branch when an order is filled. It carries no fill
  // list: the spend branch reads it from the withdraw redeemer, since carrying
  // it would repeat the list N+1 times in one transaction and grow the size
  // as N².
  Sell
  // Redeemer of the withdraw branch. SellMulti(List<(pool_ref_idx, List<Fill>)>)
  SellMulti(List<PoolFills>)
}

// Fills grouped by pool, so each PoolDatum is read once per pool.
pub type PoolFills =
  (Int, List<Fill>)

pub type Fill {
  order_in_idx: Int,
  // The output that hands PT to whoever placed the bid. On a full fill this
  // same output also carries back the leftover funds and the reserve.
  owner_ou_idx: Int,
  // Below zero means the order UTxO was filled out, leaving no remainder.
  cont_ou_idx: Int,
}
