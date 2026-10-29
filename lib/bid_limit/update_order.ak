use aiken/collection/list
use aiken/crypto.{ScriptHash, VerificationKeyHash}
use ask_limit/order as shared
use bid_limit/bid_types.{BidDatum}
use bid_limit/order.{OrderIn}
use cardano/address.{Address, Script}
use cardano/transaction.{InlineDatum, Input, Output, OutputReference}

// Update or cancel an order. It needs the owner's signature only — no withdraw,
// and no config read: nobody else's money moves, and the owner bears whatever
// they change.
//
// A cont_ou_idx below zero cancels: where the money goes once it leaves the
// script is the owner's business.
pub fn verify(
  bid_skh: ScriptHash,
  own_ref: OutputReference,
  order_in_idx: Int,
  cont_ou_idx: Int,
  inputs: List<Input>,
  outputs: List<Output>,
  extra_signatories: List<VerificationKeyHash>,
) -> Bool {
  let OrderIn { out_ref, datum, .. } =
    order.get_order_in(inputs, order_in_idx, bid_skh)
  // The index in the redeemer must point at the input being validated.
  expect out_ref == own_ref
  let BidDatum { owner_vk, pt_asset, .. } = datum
  expect list.has(extra_signatories, owner_vk)
  //
  if cont_ou_idx < 0 {
    True
  } else {
    let Output {
      address: Address { payment_credential, .. },
      datum: cont_datum,
      reference_script,
      ..
    } = shared.get_output(outputs, cont_ou_idx)
    expect payment_credential == Script(bid_skh)
    expect reference_script == None
    expect InlineDatum(raw) = cont_datum
    expect BidDatum {
      owner_vk: cont_owner,
      pt_asset: cont_pt_asset,
      offered_yield,
      bid_amount,
    }: BidDatum = raw
    // To change owner, cancel and re-create. Do not blur the two in one
    // transaction.
    expect cont_owner == owner_vk
    // Changing market, likewise. On the ask side this comes free because the PT
    // sits in the value and cannot be changed; here it sits in the datum, so
    // without this one order could straddle two PTs.
    expect cont_pt_asset == pt_asset
    expect offered_yield > 0
    (bid_amount > 0)?
  }
}
