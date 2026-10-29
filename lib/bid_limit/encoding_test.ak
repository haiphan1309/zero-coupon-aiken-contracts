//// Pins the CBOR shapes that on-chain and off-chain must agree on. Change a
//// shape on one side and forget the other, and this test goes red rather than
//// the validator refusing every transaction once the UTxO is already on chain.
////
//// ⚠️ The strings below are the source of truth, not the other way round.

use aiken/cbor
use bid_limit/bid_types.{BidDatum,
  BidLimitAction, Fill, Sell, SellMulti, Update}

const owner_vk = #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"

const pool_pid = #"b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0"

const pt_tn = #"5054"

fn datum() -> BidDatum {
  BidDatum {
    owner_vk,
    pt_asset: (pool_pid, pt_tn),
    offered_yield: 1_500,
    bid_amount: 1_000_000_000,
  }
}

/// `pt_asset` is a TUPLE, and Aiken encodes a two-element tuple as an
/// **indefinite list** `9f … ff`, NOT as `Constr 0`. No field of `AskDatum` has
/// this shape, so the ask serializer offers no precedent to copy — this is the
/// first thing someone writing the off-chain side gets wrong.
test bid_datum_shape() {
  cbor.serialise(datum()) == #"d8799f581ca1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a19f581cb0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0425054ff1905dc1a3b9aca00ff"
}

test bid_datum_round_trips() {
  expect Some(raw) = cbor.deserialise(cbor.serialise(datum()))
  expect d: BidDatum = raw
  d == datum()
}

/// Constructor numbers: Update = 0, Sell = 1, SellMulti = 2.
///
/// This order must NOT change once off-chain has been written against it. New
/// variants go on the end.
test indexer_constructor_numbers() {
  and {
    // constr 0 carrying one Int; -1 encodes as 0x20
    cbor.serialise(Update(-1)) == #"d8799f20ff",
    // constr 1, no fields
    cbor.serialise(Sell) == #"d87a80",
  }
}

/// SellMulti: constr 2, carrying `List<(Int, List<Fill>)>`. Both `PoolFills` and
/// the list are indefinite lists; `Fill` is constr 0 with three Ints.
test sell_multi_shape() {
  let v =
    SellMulti(
      [(0, [Fill { order_in_idx: 1, owner_ou_idx: 2, cont_ou_idx: -1 }])],
    )
  cbor.serialise(v) == #"d87b9f9f9f009fd8799f010220ffffffffff"
}

test fill_round_trips() {
  let f = Fill { order_in_idx: 3, owner_ou_idx: 5, cont_ou_idx: -1 }
  expect Some(raw) = cbor.deserialise(cbor.serialise(f))
  expect g: Fill = raw
  g == f
}

/// `cont_ou_idx < 0` means "filled out" and `Update(< 0)` means "cancel". The
/// negative numbers have to encode, rather than being a convention off-chain
/// invents for itself.
test negative_index_is_representable() {
  expect Some(raw) = cbor.deserialise(cbor.serialise(Update(-1)))
  expect u: bid_types.BidIndexer = raw
  u == Update(-1)
}

/// `BidLimitAction` is what off-chain builds as the redeemer — it wraps
/// `BidIndexer` together with the three indices. Both shapes that actually go
/// into a transaction are pinned here.
test spend_redeemer_shape() {
  let r =
    BidLimitAction {
      indexers: Sell,
      order_in_idx: 3,
      config_ref_idx: 0,
      fee_ou_idx: 0,
    }
  cbor.serialise(r) == #"d8799fd87a80030000ff"
}

/// The withdraw redeemer: it carries the entire fill list. This is the only
/// copy of the list in the transaction — each spend redeemer holds just `Sell`
/// plus one index.
test withdraw_redeemer_shape() {
  let r =
    BidLimitAction {
      indexers: SellMulti(
        [(0, [Fill { order_in_idx: 1, owner_ou_idx: 2, cont_ou_idx: -1 }])],
      ),
      order_in_idx: 0,
      config_ref_idx: 1,
      fee_ou_idx: 2,
    }
  cbor.serialise(r) == #"d8799fd87b9f9f9f009fd8799f010220ffffffffff000102ff"
}

test action_round_trips() {
  let r =
    BidLimitAction {
      indexers: Update(-1),
      order_in_idx: 7,
      config_ref_idx: 0,
      fee_ou_idx: 0,
    }
  expect Some(raw) = cbor.deserialise(cbor.serialise(r))
  expect back: BidLimitAction = raw
  back == r
}
