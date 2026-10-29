use aiken/collection/list
use aiken/crypto.{ScriptHash}
use ask_limit/ask_types.{ExchangeConfig}
use ask_limit/order.{PoolRef} as shared
use ask_limit/price as ask_price
use bid_limit/bid_types.{BidDatum, Fill, PoolFills}
use bid_limit/order.{OrderIn, OrderReserves}
use bid_limit/price
use cardano/assets.{Value}
use cardano/transaction.{InlineDatum, Input, Output}
use daken/tokens

// State accumulated while walking every fill in the transaction. As in
// ask_limit: last_owner_ou and last_cont_ou force output indices to increase
// strictly, because if two fills shared one output, that output would only have
// to cover the larger fill rather than the sum of both.
type Acc {
  seen_orders: List<Int>,
  fee_owed: Value,
  last_owner_ou: Int,
  last_cont_ou: Int,
}

pub fn verify(
  bid_skh: ScriptHash,
  ExchangeConfig { fee_addr: _, buyer_fee, seller_fee, pt_policies }: ExchangeConfig,
  pool_fills: List<PoolFills>,
  inputs: List<Input>,
  reference_inputs: List<Input>,
  outputs: List<Output>,
  fee_val: Value,
  tx_start: Int,
) -> Bool {
  expect buyer_fee >= 0
  expect seller_fee >= 0
  // The fee ceiling is a constant, not a calculation, so it is shared with
  // ask_limit — fee policy deliberately runs off one shared config. What is NOT
  // shared is the arithmetic in `ask_limit/price`: those functions round the
  // other way.
  expect buyer_fee <= ask_price.max_fee_rate
  expect seller_fee <= ask_price.max_fee_rate
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
          bid_skh,
          buyer_fee,
          seller_fee,
          pt_policies,
          inputs,
          reference_inputs,
          outputs,
          tx_start,
        )
      },
    )
  shared.value_covers(fee_val, fee_owed)?
}

fn verify_pool_group(
  (pool_ref_idx, fills): PoolFills,
  acc: Acc,
  bid_skh: ScriptHash,
  buyer_fee: Int,
  seller_fee: Int,
  pt_policies: List<ByteArray>,
  inputs: List<Input>,
  reference_inputs: List<Input>,
  outputs: List<Output>,
  tx_start: Int,
) -> Acc {
  // An empty group is vacuously satisfied exactly as an empty list is — the
  // same hole in another shape.
  expect fills != []
  //
  let pool = shared.get_pool_ref(reference_inputs, pool_ref_idx, pt_policies)
  let duration = price.duration_of(pool.supply_maturity, tx_start)
  // Past maturity the price is face value, so the bidder pays face value PLUS
  // the maker fee for something worth exactly face value — losing precisely
  // that fee. ask_limit needs no such block, because there the losing side is
  // the taker, who acts deliberately; here it is the maker, sitting still, and
  // a bid order has no expiry, so one forgotten order becomes a free option for
  // anyone holding matured PT. With this blocked, the owner can still cancel
  // and take the money back.
  expect duration > 0
  list.foldl(
    fills,
    acc,
    fn(fill, inner) {
      verify_fill(
        fill,
        inner,
        bid_skh,
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
  bid_skh: ScriptHash,
  pool: PoolRef,
  duration: Int,
  buyer_fee: Int,
  seller_fee: Int,
  inputs: List<Input>,
  outputs: List<Output>,
) -> Acc {
  // The same order twice in the fill list breaks the one-to-one relation
  // between order and fill — the invariant every other constraint leans on.
  expect !list.has(seen_orders, order_in_idx)
  //
  let OrderIn { address: order_addr, value: order_val, datum, .. } =
    order.get_order_in(inputs, order_in_idx, bid_skh)
  let BidDatum { owner_vk, pt_asset, offered_yield, bid_amount } = datum
  //
  // The order must point at the market this pool reference input produces.
  // Without this step a taker points at a different pool and takes a longer
  // supply_maturity to push the price down.
  let (pt_pid, pt_tn) = pt_asset
  expect pt_pid == pool.pool_pid
  expect pt_tn == pool.pt_tn
  // pt_bought is read from the PT output. If the origin token were the PT
  // itself, that read would count cash_back as well, creating a fixed point:
  // the taker delivers no real PT and still draws the money out. Unreachable
  // under the current allowlist, but one line is cheaper than an argument.
  expect pt_asset != pool.origin_token
  //
  // Create runs through no validator, so a datum may carry anything at all.
  expect offered_yield > 0
  // Redundant by design: `cash_out > 0` together with `cash_out <= bid_amount`
  // already covers this line, so no mutation can kill it. Kept because it
  // states the datum's invariant right where the datum is read — do not delete
  // it just because no test objects.
  expect bid_amount > 0
  expect owner_ou_idx > last_owner_ou
  //
  let OrderReserves { reserve, origin_reserve } =
    order.split_bid_value(order_val, pool.origin_token, bid_amount)
  //
  let Output {
    address: owner_addr,
    value: owner_val,
    datum: owner_datum,
    reference_script: owner_ref,
  } = shared.get_output(outputs, owner_ou_idx)
  //
  let pt_bought = assets.quantity_of(owner_val, pt_pid, pt_tn)
  // Redundant by design, like `bid_amount > 0`: `pt_bought = 0` gives
  // `price = 0`, so `cash_out > 0` catches it first.
  expect pt_bought > 0
  //
  let amount = price.price_floor_of(pt_bought, offered_yield, duration)
  let b_fee = price.maker_fee_of(amount, buyer_fee)
  let s_fee = price.taker_fee_of(amount, seller_fee)
  let cash_out = amount + b_fee
  expect cash_out > 0
  // Without this line bid_left goes negative, and on the full-fill branch a
  // negative cash_back makes the output condition hold always.
  expect cash_out <= bid_amount
  let bid_left = bid_amount - cash_out
  //
  // `reserve` and `origin_reserve` are the part that does not belong to this
  // fill. On a full fill the order UTxO disappears, so both must return to the
  // owner through the PT output; on a partial fill the continuation already
  // holds them, so both are zero here. Leaving `origin_reserve` in place on the
  // latter branch would demand the taker pay it a second time out of pocket,
  // and no transaction built to spec could be constructed.
  let (cash_back, ada_back, origin_back, next_cont) =
    if cont_ou_idx < 0 {
      // Filled out. This threshold does two things: it blocks griefing —
      // without it, pt_bought = 2 for cash_out = 1, so roughly one unit of
      // value plus network fees erases any bid order from the book — and it
      // makes the choice of branch a decidable one.
      expect bid_left < pool.min_borrow_amount
      (bid_left, reserve, origin_reserve, last_cont_ou)
    } else {
      expect cont_ou_idx > last_cont_ou
      // Leave no dust: the money that remains must still be tradeable.
      expect bid_left >= pool.min_borrow_amount
      let Output {
        address: cont_addr,
        value: cont_val,
        datum: cont_datum,
        reference_script,
      } = shared.get_output(outputs, cont_ou_idx)
      // Keep the address exactly, the owner's stake credential included.
      expect cont_addr == order_addr
      expect reference_script == None
      expect InlineDatum(raw) = cont_datum
      expect cont_dt: BidDatum = raw
      expect
        cont_dt == BidDatum {
          owner_vk,
          pt_asset,
          offered_yield,
          bid_amount: bid_left,
        }
      expect
        order.cont_holds(
          cont_val,
          pool.origin_token,
          bid_left,
          reserve,
          origin_reserve,
        )
      (0, 0, 0, cont_ou_idx)
    }
  //
  expect owner_addr == shared.owner_address(order_addr, owner_vk)
  expect owner_ref == None
  // Tag the output with this validator's own script hash. Without the tag, a
  // bid_limit validator of another generation running in the same transaction
  // is satisfied by that very output, and the order's owner loses the whole
  // proceeds of the second order.
  expect InlineDatum(owner_tag) = owner_datum
  expect tag: ByteArray = owner_tag
  expect tag == bid_skh
  //
  let (origin_pid, origin_tn) = pool.origin_token
  // When the origin is ADA, the change and the reserve share one field, so they
  // have to be summed and compared once. Comparing twice, independently, only
  // requires the larger side to hold.
  expect
    if tokens.is_ada(pool.origin_token) {
      assets.lovelace_of(owner_val) >= cash_back + ada_back
    } else {
      assets.quantity_of(owner_val, origin_pid, origin_tn) >= cash_back + origin_back && assets.lovelace_of(
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
