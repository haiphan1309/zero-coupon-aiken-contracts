//// Test data builders for ask_limit.
////
//// The validator takes a whole `Transaction`, so testing it means hand-building
//// all seventeen of its fields plus each `Input` and `Output`. Written out in
//// every test that is some forty lines of copy-paste, times a few dozen
//// scenarios. This module lets each test state only what it changes about the
//// ordinary path.

use aiken/interval
use ask_limit/ask_types.{AskDatum, ExchangeConfig}
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

pub const ask_skh = #"a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0"

pub const pool_pid = #"b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0"

pub const pool_id = #"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0"

/// A second pool of the same deployment generation: same policy id, different
/// asset name.
pub const pool_id2 = #"c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1"

pub const junk_pid =
  #"9090909090909090909090909090909090909090909090909090909090"

pub const cfg_pid = #"d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0"

pub const cfg_tn = #"41736b4c696d6974"

pub const origin_pid =
  #"e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0"

pub const origin_tn = #"74444a4544"

pub const alice_vk = #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"

pub const bob_vk = #"b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1"

pub const fee_vk = #"f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1"

pub const min_ada = 2_000_000

pub const min_borrow = 1_000_000

/// The duration left in the worked example: 90 "days" on the compressed
/// environment, which is 9 real hours.
pub const duration = 90 * 360_000

/// The validity window used by tests at the `sc_ask_limit.withdraw` level. It
/// spans 300 slots, under the `env.ttl = 360` ceiling.
pub const from_slot = 70_000_000 - 300

pub const to_slot = 70_000_000

/// Price is anchored to the upper bound, so `tx_end` is where every price
/// figure follows from.
pub fn tx_end() -> Int {
  time.slot_to_begin_posix_time(to_slot, time.get_slot_config_network_preview())
}

pub fn supply_maturity() -> Int {
  tx_end() + duration
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

// ---------------------------------------------------------------- addresses

pub fn wallet_addr(vk: ByteArray) -> Address {
  Address { payment_credential: VerificationKey(vk), stake_credential: None }
}

/// The order address: ask_limit's script hash plus the seller's stake
/// credential, so every seller gets a different address.
pub fn order_addr(owner_vk: ByteArray) -> Address {
  Address {
    payment_credential: Script(ask_skh),
    stake_credential: Some(Inline(VerificationKey(owner_vk))),
  }
}

/// The seller's payout address, inheriting the stake credential from the order
/// UTxO.
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

pub fn order_in(ix: Int, owner_vk: ByteArray, yield: Int, pt_qty: Int) -> Input {
  order_in_of(ix, owner_vk, yield, pt_qty, pool_pid, pt_tn())
}

/// The full form: allows placing another pool's PT, to build failing cases.
pub fn order_in_of(
  ix: Int,
  owner_vk: ByteArray,
  yield: Int,
  pt_qty: Int,
  pid: PolicyId,
  tn: AssetName,
) -> Input {
  Input {
    output_reference: out_ref(ix),
    output: ob.new(order_addr(owner_vk))
      |> ob.add_lovelace(min_ada)
      |> ob.add_asset(pid, tn, pt_qty)
      |> ob.add_inline_datum(AskDatum { owner_vk, requested_yield: yield }),
  }
}

/// The pool UTxO used as a reference input. The pool NFT has a 28-byte asset
/// name and the same policy as the PT; the validator takes the policy from the
/// address's payment credential, so it cannot be pointed at a self-made UTxO at
/// some other address.
pub fn pool_ref(ix: Int, maturity: Int) -> Input {
  pool_ref_of(ix, maturity, pool_pid, pool_id, origin_token())
}

/// A pool whose supply token is ADA — the price branch that merges the sale
/// proceeds with the returned ADA.
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

pub fn payout_out(owner_vk: ByteArray, origin_qty: Int, lovelace: Int) -> Output {
  ob.new(payout_addr(owner_vk))
    |> ob.add_lovelace(lovelace)
    |> ob.add_asset(origin_pid, origin_tn, origin_qty)
    |> ob.add_inline_datum(ask_skh)
}

/// Payment in ADA — for a pool whose supply token is ADA.
pub fn payout_out_ada(owner_vk: ByteArray, lovelace: Int) -> Output {
  ob.new(payout_addr(owner_vk))
    |> ob.add_lovelace(lovelace)
    |> ob.add_inline_datum(ask_skh)
}

pub fn cont_out(owner_vk: ByteArray, yield: Int, pt_qty: Int) -> Output {
  ob.new(order_addr(owner_vk))
    |> ob.add_lovelace(min_ada)
    |> ob.add_asset(pool_pid, pt_tn(), pt_qty)
    |> ob.add_inline_datum(AskDatum { owner_vk, requested_yield: yield })
}

/// A remainder order holding the PT of a named pool — for multi-pool tests.
pub fn cont_out_of(
  owner_vk: ByteArray,
  yield: Int,
  pt_qty: Int,
  tn: AssetName,
) -> Output {
  ob.new(order_addr(owner_vk))
    |> ob.add_lovelace(min_ada)
    |> ob.add_asset(pool_pid, tn, pt_qty)
    |> ob.add_inline_datum(AskDatum { owner_vk, requested_yield: yield })
}

/// A self-made UTxO at a wallet address carrying a token named like the pool
/// NFT. Used to show the pool reference input cannot be forged.
pub fn fake_pool_output(maturity: Int) -> Output {
  ob.new(wallet_addr(bob_vk))
    |> ob.add_lovelace(min_ada)
    |> ob.add_asset(pool_pid, pool_id, 1)
    |> ob.add_inline_datum(pool_datum_of(maturity, origin_token()))
}

pub fn fee_out(origin_qty: Int) -> Output {
  ob.new(wallet_addr(fee_vk))
    |> ob.add_lovelace(min_ada)
    |> ob.add_asset(origin_pid, origin_tn, origin_qty)
    |> ob.add_inline_datum(ask_skh)
}

pub fn fee_out_ada(lovelace: Int) -> Output {
  ob.new(wallet_addr(fee_vk))
    |> ob.add_lovelace(lovelace)
    |> ob.add_inline_datum(ask_skh)
}

pub fn fee_value_ada(lovelace: Int) -> Value {
  assets.from_lovelace(lovelace)
}

pub fn fee_value(origin_qty: Int) -> Value {
  assets.from_lovelace(min_ada) |> assets.add(origin_pid, origin_tn, origin_qty)
}

// ------------------------------------------------------------ transaction

/// Build a `Transaction` from `transaction.placeholder`, setting only the
/// fields ask_limit actually reads. The other thirteen keep their defaults.
///
/// Note: do NOT use `tb.add_input` / `tb.add_output` to load the lists. They
/// prepend, which reverses the order. Every test here turns on indices, so
/// inputs and outputs must sit in ledger order — pass the lists straight in.
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
  // The eleven-field PoolDatum of the build running on Preview. ask_limit reads
  // only supply_token, supply_maturity and min_borrow_amount; the rest are here
  // so the datum's shape matches the chain exactly — a wrong shape means a
  // parse failure on every fill.
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
