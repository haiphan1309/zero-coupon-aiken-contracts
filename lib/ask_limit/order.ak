use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{ScriptHash}
use aiken/primitive/bytearray
use ask_limit/ask_types.{AskDatum}
use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/transaction.{InlineDatum, Input, Output, OutputReference}
use constants
use daken/tokens
use types.{PoolDatum}
use utils

pub type OrderIn {
  out_ref: OutputReference,
  address: Address,
  value: Value,
  datum: AskDatum,
  pt_pid: PolicyId,
  pt_tn: AssetName,
  pt_qty: Int,
}

pub type PoolRef {
  pool_pid: PolicyId,
  pt_tn: AssetName,
  origin_token: (PolicyId, AssetName),
  supply_maturity: Int,
  min_borrow_amount: Int,
}

// Read an order UTxO out of the inputs by its ledger index.
// The value must be ADA plus exactly one token; that token has to be a valid
// PT, which the caller checks.
pub fn get_order_in(
  inputs: List<Input>,
  idx: Int,
  ask_skh: ScriptHash,
) -> OrderIn {
  let Input {
    output_reference,
    output: Output { address, value, datum, reference_script },
  } = inputs |> utils.tail_list_by_idx(idx) |> builtin.head_list
  let Address { payment_credential, .. } = address
  expect payment_credential == Script(ask_skh)
  expect reference_script == None
  expect InlineDatum(raw) = datum
  expect ask_datum: AskDatum = raw
  let (pt_pid, pt_tn, pt_qty) = single_token_of(value)
  OrderIn {
    out_ref: output_reference,
    address,
    value,
    datum: ask_datum,
    pt_pid,
    pt_tn,
    pt_qty,
  }
}

// An order UTxO may hold ADA and exactly one kind of token.
// Loosening this would let junk tokens be stuffed in and forced on the buyer.
pub fn single_token_of(value: Value) -> (PolicyId, AssetName, Int) {
  expect [token] =
    value
      |> assets.flatten_with(
          fn(pid, tn, qty) {
            if tokens.is_ada((pid, tn)) {
              None
            } else {
              Some((pid, tn, qty))
            }
          },
        )
  token
}

// Read the pool's reference input and derive that pool's valid PT name.
//
// The pool NFT, the PT and the YT share one policy id, the pool script hash,
// and differ only in asset name: the pool NFT is 28 bytes, PT and YT are 31
// bytes with different prefixes. The policy is taken from the address's payment
// credential, so it cannot be pointed at a self-made UTxO.
pub fn get_pool_ref(
  reference_inputs: List<Input>,
  idx: Int,
  pt_policies: List<PolicyId>,
) -> PoolRef {
  let Input {
    output: Output {
      address: Address { payment_credential, .. },
      value,
      datum,
      ..
    },
    ..
  } = reference_inputs |> utils.tail_list_by_idx(idx) |> builtin.head_list
  expect Script(pool_pid) = payment_credential
  expect list.has(pt_policies, pool_pid)
  //
  expect [pool_id] =
    assets.tokens(value, pool_pid)
      |> dict.to_pairs
      |> list.foldr(
          [],
          fn(Pair(tn, qty), acc) {
            if bytearray.length(tn) == constants.number_28 && qty == 1 {
              [tn, ..acc]
            } else {
              acc
            }
          },
        )
  //
  expect InlineDatum(raw) = datum
  expect PoolDatum {
    supply_token: (_yield_token, origin_token),
    supply_maturity,
    min_borrow_amount,
    ..
  }: PoolDatum = raw
  PoolRef {
    pool_pid,
    pt_tn: utils.get_pt_name(pool_id),
    origin_token,
    supply_maturity,
    min_borrow_amount,
  }
}

// The seller's payout address: the payment credential comes from owner_vk in
// the datum, the stake credential is inherited from the order UTxO itself.
// Inheriting it stops the buyer altering the stake part and taking the seller's
// delegation rewards.
pub fn owner_address(order_addr: Address, owner_vk: ByteArray) -> Address {
  let Address { stake_credential, .. } = order_addr
  Address { payment_credential: VerificationKey(owner_vk), stake_credential }
}

pub fn get_output(outputs: List<Output>, idx: Int) -> Output {
  outputs |> utils.tail_list_by_idx(idx) |> builtin.head_list
}

// Every value in `owed` must appear in `paid` in no smaller quantity.
pub fn value_covers(paid: Value, owed: Value) -> Bool {
  owed
    |> assets.flatten
    |> list.all(fn((pid, tn, qty)) { assets.quantity_of(paid, pid, tn) >= qty })
}

/// Read and check the fee output.
///
/// It does not use `utils.validate_and_get_fee_val`, because that helper
/// requires `NoDatum`, whereas here the fee output has to carry the `ask_skh`
/// tag. Without the tag, two live deployment generations could share one fee
/// output and the protocol would collect only half — the same hole as on the
/// seller payout.
pub fn get_fee_value(
  outputs: List<Output>,
  idx: Int,
  expected_addr: Address,
  ask_skh: ScriptHash,
) -> Value {
  if idx < 0 {
    assets.zero
  } else {
    let Output { address, value, datum, reference_script } =
      get_output(outputs, idx)
    expect address == expected_addr
    expect reference_script == None
    expect InlineDatum(raw) = datum
    expect tag: ByteArray = raw
    expect tag == ask_skh
    value
  }
}
