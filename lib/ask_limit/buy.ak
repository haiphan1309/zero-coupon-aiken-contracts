use aiken/collection/list
use aiken/crypto.{ScriptHash}
use ask_limit/ask_types.{AskDatum, ExchangeConfig, Fill, PoolFills}
use ask_limit/order.{OrderIn, PoolRef}
use ask_limit/price
use cardano/assets.{Value}
use cardano/transaction.{InlineDatum, Input, Output}
use daken/tokens

// State accumulated while walking every fill in the transaction.
//
// last_owner_ou and last_cont_ou force output indices to increase strictly. If
// two fills shared one output, that output would only have to cover the larger
// fill rather than the sum of both, and the seller would lose the difference.
// Requiring a strict increase is the cheapest way to forbid sharing, and it
// also pins off-chain to one fixed output order.
type Acc {
  seen_orders: List<Int>,
  fee_owed: Value,
  last_owner_ou: Int,
  last_cont_ou: Int,
}

pub fn verify(
  ask_skh: ScriptHash,
  ExchangeConfig { fee_addr: _, buyer_fee, seller_fee, pt_policies }: ExchangeConfig,
  pool_fills: List<PoolFills>,
  inputs: List<Input>,
  reference_inputs: List<Input>,
  outputs: List<Output>,
  fee_val: Value,
  tx_end: Int,
) -> Bool {
  expect buyer_fee >= 0
  expect seller_fee >= 0
  expect buyer_fee <= price.max_fee_rate
  expect seller_fee <= price.max_fee_rate
  //
  // On an empty list every constraint below holds vacuously and withdraw passes
  // clean, which would let anyone build a withdraw-only transaction to sweep
  // the reward account.
  expect pool_fills != []
  //
  let Acc { fee_owed, .. } =
    list.foldl(
      pool_fills,
      Acc {
        seen_orders: [],
        fee_owed: assets.zero,
        last_owner_ou: -1,
        last_cont_ou: -1,
      },
      fn(pool_fill, acc) {
        verify_pool_group(
          pool_fill,
          acc,
          ask_skh,
          buyer_fee,
          seller_fee,
          pt_policies,
          inputs,
          reference_inputs,
          outputs,
          tx_end,
        )
      },
    )
  order.value_covers(fee_val, fee_owed)?
}

fn verify_pool_group(
  (pool_ref_idx, fills): PoolFills,
  acc: Acc,
  ask_skh: ScriptHash,
  buyer_fee: Int,
  seller_fee: Int,
  pt_policies: List<ByteArray>,
  inputs: List<Input>,
  reference_inputs: List<Input>,
  outputs: List<Output>,
  tx_end: Int,
) -> Acc {
  // A group where no fill survived `pool_fills != []` above is then vacuously
  // satisfied, exactly as an empty list is — the same hole in another shape.
  expect fills != []
  //
  let pool = order.get_pool_ref(reference_inputs, pool_ref_idx, pt_policies)
  let duration = price.duration_of(pool.supply_maturity, tx_end)
  list.foldl(
    fills,
    acc,
    fn(fill, inner) {
      verify_fill(
        fill,
        inner,
        ask_skh,
        pool,
        duration,
        buyer_fee,
        seller_fee,
        inputs,
        outputs,
      )
    },
  )
}

fn verify_fill(
  Fill { order_in_idx, owner_ou_idx, cont_ou_idx }: Fill,
  Acc { seen_orders, fee_owed, last_owner_ou, last_cont_ou }: Acc,
  ask_skh: ScriptHash,
  pool: PoolRef,
  duration: Int,
  buyer_fee: Int,
  seller_fee: Int,
  inputs: List<Input>,
  outputs: List<Output>,
) -> Acc {
  // The same order appearing twice in the fill list breaks the one-to-one
  // relation between order and fill. Not exploitable in the present shape, but
  // this invariant is what every other constraint leans on.
  expect !list.has(seen_orders, order_in_idx)
  //
  let order_in = order.get_order_in(inputs, order_in_idx, ask_skh)
  let OrderIn {
    address: order_addr,
    value: order_val,
    datum,
    pt_pid,
    pt_tn,
    pt_qty,
    ..
  } = order_in
  let AskDatum { owner_vk, requested_yield } = datum
  // The order must hold the PT of the pool it references.
  expect pt_pid == pool.pool_pid
  expect pt_tn == pool.pt_tn
  // Create runs through no validator, so a datum may carry any yield at all. A
  // negative yield large enough drives the denominator to zero or below, the
  // price turns negative, and the condition for paying the seller is satisfied
  // by any output — the buyer takes the PT for nothing.
  expect requested_yield > 0
  expect owner_ou_idx > last_owner_ou
  //
  let (pt_sold, ada_back, next_cont) =
    if cont_ou_idx < 0 {
      // Bought out: all the PT leaves the script, and the ADA locked in the
      // order UTxO goes back to the seller.
      (pt_qty, assets.lovelace_of(order_val), last_cont_ou)
    } else {
      expect cont_ou_idx > last_cont_ou
      let Output {
        address: cont_addr,
        value: cont_val,
        datum: cont_datum,
        reference_script,
      } = order.get_output(outputs, cont_ou_idx)
      // Keep the address exactly, the seller's stake credential included.
      expect cont_addr == order_addr
      expect reference_script == None
      expect InlineDatum(raw) = cont_datum
      expect cont_dt: AskDatum = raw
      expect cont_dt == datum
      // The locked ADA may not be drawn down.
      expect assets.lovelace_of(cont_val) >= assets.lovelace_of(order_val)
      let (c_pid, c_tn, pt_left) = order.single_token_of(cont_val)
      expect c_pid == pt_pid
      expect c_tn == pt_tn
      // Leave no dust: whatever remains must still be tradeable.
      expect pt_left >= pool.min_borrow_amount
      (pt_qty - pt_left, 0, cont_ou_idx)
    }
  expect pt_sold > 0
  //
  let amount = price.price_of(pt_sold, requested_yield, duration)
  let s_fee = price.seller_fee_of(amount, seller_fee)
  let b_fee = price.buyer_fee_of(amount, buyer_fee)
  let net = amount - s_fee
  //
  let Output {
    address: owner_addr,
    value: owner_val,
    datum: owner_datum,
    reference_script: owner_ref,
  } = order.get_output(outputs, owner_ou_idx)
  expect owner_addr == order.owner_address(order_addr, owner_vk)
  expect owner_ref == None
  // Tag the payout output with this validator's own script hash. Untagged, the
  // output carries only an address and an amount, so an ask_limit of another
  // generation in the same transaction is satisfied by that same output: the
  // seller rests orders on both, the buyer pays once, both pass, and the seller
  // loses the second order's proceeds. Within one generation the strictly
  // increasing `owner_ou_idx` already prevents it.
  expect InlineDatum(owner_tag) = owner_datum
  expect tag: ByteArray = owner_tag
  expect tag == ask_skh
  //
  let (origin_pid, origin_tn) = pool.origin_token
  // When the origin token is ADA, the sale proceeds and the returned ADA share
  // one field, so they have to be summed and compared once. Comparing twice,
  // independently, only requires the larger side to hold.
  expect
    if tokens.is_ada(pool.origin_token) {
      assets.lovelace_of(owner_val) >= net + ada_back
    } else {
      assets.quantity_of(owner_val, origin_pid, origin_tn) >= net && assets.lovelace_of(
        owner_val,
      ) >= ada_back
    }
  //
  Acc {
    seen_orders: [order_in_idx, ..seen_orders],
    fee_owed: assets.add(fee_owed, origin_pid, origin_tn, s_fee + b_fee),
    last_owner_ou: owner_ou_idx,
    last_cont_ou: next_cont,
  }
}
