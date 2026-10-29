use aiken/builtin
use aiken/crypto.{ScriptHash}
use ask_limit/order as shared
use bid_limit/bid_types.{BidDatum}
use cardano/address.{Address, Script}
use cardano/assets.{Value}
use cardano/transaction.{InlineDatum, Input, Output, OutputReference}
use daken/tokens
use utils

// Helpers shared with ask_limit are NOT copied here — `get_pool_ref`,
// `get_output`, `value_covers`, `owner_address`, `single_token_of`,
// `get_fee_value` carry no side's semantics. What must NOT be reused is
// `ask_limit/price`: the names read correctly for this side but round the other
// way. See `bid_limit/price`.
//
// ⚠️ `lib/ask_limit/` is read-only from here on. Its hash must stay still,
// because the Ask book is live; changing it "for bid" orphans every resting
// order. Copy into `bid_limit` instead.

pub type OrderIn {
  out_ref: OutputReference,
  address: Address,
  value: Value,
  datum: BidDatum,
}

/// What an order UTxO holds that does NOT belong to the order: `reserve` is
/// lovelace beyond `bid_amount`, `origin_reserve` is origin token beyond it.
/// When the origin is ADA the two share one field, so `origin_reserve` is
/// always 0.
///
/// Both must return to the owner when the order closes, and both must be zero
/// on the partial-fill branch, where the continuation already holds them.
/// Omitting `origin_reserve` leaves excess tokens unprotected; demanding it in
/// both places makes the taker pay twice.
pub type OrderReserves {
  reserve: Int,
  origin_reserve: Int,
}

/// Read an order UTxO out of the inputs by its ledger index.
pub fn get_order_in(
  inputs: List<Input>,
  idx: Int,
  bid_skh: ScriptHash,
) -> OrderIn {
  let Input {
    output_reference,
    output: Output { address, value, datum, reference_script },
  } = inputs |> utils.tail_list_by_idx(idx) |> builtin.head_list
  let Address { payment_credential, .. } = address
  expect payment_credential == Script(bid_skh)
  expect reference_script == None
  expect InlineDatum(raw) = datum
  expect bid_datum: BidDatum = raw
  OrderIn { out_ref: output_reference, address, value, datum: bid_datum }
}

/// Split an order UTxO's value into the order's money and the excess.
///
/// Origin is ADA: the UTxO may hold ADA only. Loosening this would let junk
/// tokens be stuffed into an order and forced on the seller — the same hole
/// `single_token_of` closes on the other side.
pub fn split_bid_value(
  value: Value,
  origin_token: (ByteArray, ByteArray),
  bid_amount: Int,
) -> OrderReserves {
  let (origin_pid, origin_tn) = origin_token
  if tokens.is_ada(origin_token) {
    expect [] = value |> assets.flatten_with(non_ada)
    let reserve = assets.lovelace_of(value) - bid_amount
    expect reserve >= 0
    OrderReserves { reserve, origin_reserve: 0 }
  } else {
    let (pid, tn, qty) = shared.single_token_of(value)
    expect pid == origin_pid
    expect tn == origin_tn
    let origin_reserve = qty - bid_amount
    expect origin_reserve >= 0
    OrderReserves { reserve: assets.lovelace_of(value), origin_reserve }
  }
}

/// The remainder order must hold the order's money PLUS whatever excess does
/// not belong to this fill.
///
/// It sits next to `split_bid_value` because the two are halves of one rule: one
/// splits the order UTxO's value, the other checks the remainder's value. Split
/// across two files, changing the rule in one place means remembering the other.
pub fn cont_holds(
  cont_val: Value,
  origin_token: (ByteArray, ByteArray),
  bid_left: Int,
  reserve: Int,
  origin_reserve: Int,
) -> Bool {
  let (origin_pid, origin_tn) = origin_token
  if tokens.is_ada(origin_token) {
    and {
      assets.lovelace_of(cont_val) >= bid_left + reserve,
      // The original order may hold ADA only, so the remainder may too.
      // Loosening it lets a taker stuff in junk tokens and leave the order
      // unfillable.
      assets.flatten_with(cont_val, non_ada) == [],
    }
  } else {
    // Pin the token's identity rather than inferring it through
    // `quantity_of`: that inference rests on another module's
    // `min_borrow_amount > 0`, and this does not.
    let (pid, tn, qty) = shared.single_token_of(cont_val)
    and {
      pid == origin_pid,
      tn == origin_tn,
      qty >= bid_left + origin_reserve,
      assets.lovelace_of(cont_val) >= reserve,
    }
  }
}

fn non_ada(pid: ByteArray, tn: ByteArray, qty: Int) -> Option<Int> {
  if tokens.is_ada((pid, tn)) {
    None
  } else {
    Some(qty)
  }
}
