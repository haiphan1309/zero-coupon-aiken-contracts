//// Test data builders for bid_limit.
////
//// A mirror of `ask_limit/fixture`, differing in that an order holds MONEY
//// rather than PT, and the time bound is tx_start rather than tx_end.

use aiken/interval
use ask_limit/ask_types.{ExchangeConfig}
use bid_limit/bid_types.{BidDatum}
use cardano/address.{Address, Inline, Script, VerificationKey}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/transaction.{Input, Output, OutputReference, Transaction}
use daken/fixture/output_builder as ob
use daken/fixture/tx_builder as tb
use daken/time
use env
use types.{PoolDatum}
use utils

// ---------------------------------------------------------------- constants

pub const bid_skh = #"0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"

pub const pool_pid = #"b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0"

pub const pool_id = #"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0"

pub const pool_id2 = #"c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1"

pub const cfg_pid = #"d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0"

pub const cfg_tn = #"41736b4c696d6974"

pub const origin_pid =
  #"e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0"

pub const origin_tn = #"74444a4544"

pub const junk_pid =
  #"9090909090909090909090909090909090909090909090909090909090"

pub const alice_vk = #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"

pub const bob_vk = #"b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1"

pub const fee_vk = #"f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1"

pub const min_ada = 2_000_000

pub const min_borrow = 9_000_000

/// 90 "days" on the compressed environment, which is 9 real hours.
pub const duration = 90 * 360_000

pub const from_slot = 70_000_000 - 300

pub const to_slot = 70_000_000

// -------------------------------------- figures from the worked example

pub const bid_amount = 1_000_000_000

pub const reserve = 2_000_000

pub const yield = 1_500

/// Partial fill: 500 PT.
pub const pt_partial = 500_000_000

pub const price_partial = 482_166_446

pub const maker_fee_partial = 964_332

pub const taker_fee_partial = 482_167

pub const cash_out_partial = 483_130_778

pub const bid_left_partial = 516_869_222

/// Full fill: the largest PT amount bid_amount can reach.
pub const pt_full = 1_034_916_470

pub const cash_out_full = 1_000_000_000

pub const taker_fee_full = 998_004

pub const maker_fee_full = 1_996_007

/// Price is anchored to the LOWER bound — this is where bid differs from ask.
pub fn tx_start() -> Int {
  time.slot_to_begin_posix_time(
    from_slot,
    time.get_slot_config_network_preview(),
  )
}

pub fn supply_maturity() -> Int {
  tx_start() + duration
}

pub fn pt_tn() -> ByteArray {
  utils.get_pt_name(pool_id)
}

pub fn pt_tn2() -> ByteArray {
  utils.get_pt_name(pool_id2)
}

pub fn origin_token() -> (ByteArray, ByteArray) {
  (origin_pid, origin_tn)
}

pub fn config() -> ExchangeConfig {
  ExchangeConfig {
    fee_addr: wallet_addr(fee_vk),
    buyer_fee: 20,
    seller_fee: 10,
    pt_policies: [pool_pid],
  }
}

pub fn datum_of(owner_vk: ByteArray, y: Int, amount: Int) -> BidDatum {
  BidDatum {
    owner_vk,
    pt_asset: (pool_pid, pt_tn()),
    offered_yield: y,
    bid_amount: amount,
  }
}

// ---------------------------------------------------------------- addresses

pub fn wallet_addr(vk: ByteArray) -> Address {
  Address { payment_credential: VerificationKey(vk), stake_credential: None }
}

/// The order address: script hash plus the bidder's stake credential, as on the
/// ask side.
pub fn order_addr(owner_vk: ByteArray) -> Address {
  Address {
    payment_credential: Script(bid_skh),
    stake_credential: Some(Inline(VerificationKey(owner_vk))),
  }
}

/// The PT payout address, inheriting the stake credential from the order UTxO.
pub fn payout_addr(owner_vk: ByteArray) -> Address {
  Address {
    payment_credential: VerificationKey(owner_vk),
    stake_credential: Some(Inline(VerificationKey(owner_vk))),
  }
}

// ---------------------------------------------------------------- input

pub fn out_ref(ix: Int) -> OutputReference {
  OutputReference {
    transaction_id: #"0101010101010101010101010101010101010101010101010101010101010101",
    output_index: ix,
  }
}

/// A bid order whose origin token is NOT ADA: padding ADA plus exactly one
/// token, the origin.
pub fn bid_in(ix: Int, owner_vk: ByteArray, y: Int, amount: Int) -> Input {
  bid_in_of(ix, owner_vk, y, amount, amount, min_ada)
}

/// The full form: allows a token count and a lovelace amount other than
/// `bid_amount`, to build cases with an excess.
pub fn bid_in_of(
  ix: Int,
  owner_vk: ByteArray,
  y: Int,
  amount: Int,
  origin_qty: Int,
  lovelace: Int,
) -> Input {
  Input {
    output_reference: out_ref(ix),
    output: ob.new(order_addr(owner_vk))
      |> ob.add_lovelace(lovelace)
      |> ob.add_asset(origin_pid, origin_tn, origin_qty)
      |> ob.add_inline_datum(datum_of(owner_vk, y, amount)),
  }
}

/// A bid order whose origin is ADA: lovelace only, no other token.
pub fn bid_in_ada(ix: Int, owner_vk: ByteArray, y: Int, amount: Int) -> Input {
  bid_in_ada_of(ix, owner_vk, y, amount, amount + reserve)
}

pub fn bid_in_ada_of(
  ix: Int,
  owner_vk: ByteArray,
  y: Int,
  amount: Int,
  lovelace: Int,
) -> Input {
  Input {
    output_reference: out_ref(ix),
    output: ob.new(order_addr(owner_vk))
      |> ob.add_lovelace(lovelace)
      |> ob.add_inline_datum(datum_of(owner_vk, y, amount)),
  }
}

pub fn pool_ref(ix: Int, maturity: Int) -> Input {
  pool_ref_of(ix, maturity, pool_pid, pool_id, origin_token())
}

pub fn pool_ref_ada(ix: Int, maturity: Int) -> Input {
  pool_ref_of(ix, maturity, pool_pid, pool_id, ("", ""))
}

pub fn pool_ref_of(
  ix: Int,
  maturity: Int,
  pid: PolicyId,
  id: AssetName,
  origin: (PolicyId, AssetName),
) -> Input {
  Input {
    output_reference: out_ref(ix),
    output: ob.new(
      Address { payment_credential: Script(pid), stake_credential: None },
    )
      |> ob.add_lovelace(min_ada)
      |> ob.add_asset(pid, id, 1)
      |> ob.add_inline_datum(pool_datum_of(maturity, origin)),
  }
}

pub fn config_ref(ix: Int, cfg: ExchangeConfig) -> Input {
  Input {
    output_reference: out_ref(ix),
    output: ob.new(
      Address { payment_credential: Script(cfg_pid), stake_credential: None },
    )
      |> ob.add_lovelace(min_ada)
      |> ob.add_asset(cfg_pid, cfg_tn, 1)
      |> ob.add_inline_datum(cfg),
  }
}

// ---------------------------------------------------------------- output

/// The output handing PT to the bidder, origin other than ADA. `origin_qty` is
/// the change returned (0 on a partial fill).
pub fn payout_out(
  owner_vk: ByteArray,
  pt_qty: Int,
  origin_qty: Int,
  lovelace: Int,
) -> Output {
  ob.new(payout_addr(owner_vk))
    |> ob.add_lovelace(lovelace)
    |> ob.add_asset(pool_pid, pt_tn(), pt_qty)
    |> ob.add_asset(origin_pid, origin_tn, origin_qty)
    |> ob.add_inline_datum(bid_skh)
}

/// The PT output when the origin is ADA: change and reserve merge into the
/// lovelace field.
pub fn payout_out_ada(owner_vk: ByteArray, pt_qty: Int, lovelace: Int) -> Output {
  ob.new(payout_addr(owner_vk))
    |> ob.add_lovelace(lovelace)
    |> ob.add_asset(pool_pid, pt_tn(), pt_qty)
    |> ob.add_inline_datum(bid_skh)
}

pub fn cont_out(owner_vk: ByteArray, y: Int, left: Int) -> Output {
  cont_out_of(owner_vk, y, left, left, min_ada)
}

pub fn cont_out_of(
  owner_vk: ByteArray,
  y: Int,
  left: Int,
  origin_qty: Int,
  lovelace: Int,
) -> Output {
  ob.new(order_addr(owner_vk))
    |> ob.add_lovelace(lovelace)
    |> ob.add_asset(origin_pid, origin_tn, origin_qty)
    |> ob.add_inline_datum(datum_of(owner_vk, y, left))
}

pub fn cont_out_ada(owner_vk: ByteArray, y: Int, left: Int) -> Output {
  cont_out_ada_of(owner_vk, y, left, left + reserve)
}

pub fn cont_out_ada_of(
  owner_vk: ByteArray,
  y: Int,
  left: Int,
  lovelace: Int,
) -> Output {
  ob.new(order_addr(owner_vk))
    |> ob.add_lovelace(lovelace)
    |> ob.add_inline_datum(datum_of(owner_vk, y, left))
}

pub fn fee_out(origin_qty: Int) -> Output {
  ob.new(wallet_addr(fee_vk))
    |> ob.add_lovelace(min_ada)
    |> ob.add_asset(origin_pid, origin_tn, origin_qty)
    |> ob.add_inline_datum(bid_skh)
}

pub fn fee_out_ada(lovelace: Int) -> Output {
  ob.new(wallet_addr(fee_vk))
    |> ob.add_lovelace(lovelace)
    |> ob.add_inline_datum(bid_skh)
}

pub fn fee_value(origin_qty: Int) -> Value {
  assets.from_lovelace(min_ada) |> assets.add(origin_pid, origin_tn, origin_qty)
}

pub fn fee_value_ada(lovelace: Int) -> Value {
  assets.from_lovelace(lovelace)
}

// ------------------------------------------------------------ transaction

pub fn mk_tx(
  inputs: List<Input>,
  reference_inputs: List<Input>,
  outputs: List<Output>,
  extra_signatories: List<ByteArray>,
) -> Transaction {
  Transaction {
    ..tb.new(),
    inputs: inputs,
    reference_inputs: reference_inputs,
    outputs: outputs,
    extra_signatories: extra_signatories,
    validity_range: valid_range(),
  }
}

pub fn valid_range() -> interval.Interval<Int> {
  let cfg = time.get_slot_config_network_preview()
  interval.between(
    time.slot_to_begin_posix_time(from_slot, cfg),
    time.slot_to_begin_posix_time(to_slot, cfg),
  )
}

fn pool_datum_of(maturity: Int, origin: (PolicyId, AssetName)) -> PoolDatum {
  PoolDatum {
    supply_token: ((origin_pid, #"71444a4544"), origin),
    pt_supply: 1_000_000_000,
    yt_supply: 1_000_000_000,
    supply_maturity: maturity,
    collaterals: [],
    base_interest_rate: 500,
    gradient: 100,
    max_duration: env.year_in_ms,
    loan_activated: 0,
    fee_collected: False,
    min_borrow_amount: min_borrow,
  }
}
