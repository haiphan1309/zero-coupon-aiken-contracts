use aiken/collection/list
use aiken/crypto.{ScriptHash, VerificationKeyHash}
use ask_limit/ask_types.{AskDatum}
use ask_limit/order.{OrderIn}
use cardano/address.{Address, Script}
use cardano/transaction.{InlineDatum, Input, Output, OutputReference}

// Update or cancel an order. It needs the owner's signature only — no withdraw,
// and no config read: nobody else's money moves, and the owner bears whatever
// they change.
//
// A cont_ou_idx below zero cancels: where the PT goes once it leaves the script
// is the owner's business.
pub fn verify(
  ask_skh: ScriptHash,
  own_ref: OutputReference,
  order_in_idx: Int,
  cont_ou_idx: Int,
  inputs: List<Input>,
  outputs: List<Output>,
  extra_signatories: List<VerificationKeyHash>,
) -> Bool {
  let OrderIn { out_ref, datum, pt_pid, pt_tn, .. } =
    order.get_order_in(inputs, order_in_idx, ask_skh)
  // The index in the redeemer must point at the input being validated.
  expect out_ref == own_ref
  let AskDatum { owner_vk, .. } = datum
  expect list.has(extra_signatories, owner_vk)
  //
  if cont_ou_idx < 0 {
    True
  } else {
    let Output {
      address: Address { payment_credential, .. },
      value,
      datum: cont_datum,
      reference_script,
    } = order.get_output(outputs, cont_ou_idx)
    expect payment_credential == Script(ask_skh)
    expect reference_script == None
    expect InlineDatum(raw) = cont_datum
    expect AskDatum { owner_vk: cont_owner, requested_yield }: AskDatum = raw
    // To change owner, cancel and re-create. Do not blur the two in one
    // transaction.
    expect cont_owner == owner_vk
    expect requested_yield > 0
    let (c_pid, c_tn, _c_qty) = order.single_token_of(value)
    expect c_pid == pt_pid
    // No check that the quantity is above zero: a Cardano `Value` never holds
    // an entry of quantity 0 — `assets.add(v, _, _, 0)` is a no-op, and a total
    // reaching 0 drops the key. A remainder order with no PT fails earlier, at
    // `single_token_of`.
    (c_tn == pt_tn)?
  }
}
