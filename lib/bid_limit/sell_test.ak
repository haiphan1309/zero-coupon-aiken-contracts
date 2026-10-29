//// Tests for `bid_limit/sell`. They call `sell.verify` directly, not through
//// the validator, so each test states only what it changes about the ordinary
//// path.

use ask_limit/ask_types.{ExchangeConfig}
use bid_limit/bid_types.{BidDatum, Fill}
use bid_limit/fixture.{
  alice_vk, bid_amount, bid_left_partial, bob_vk, cash_out_full,
  cash_out_partial, maker_fee_full, maker_fee_partial, min_ada, min_borrow,
  pt_full, pt_partial, reserve, taker_fee_full, taker_fee_partial, yield,
}
use bid_limit/sell
use cardano/assets.{Value}
use cardano/transaction.{Input, Output}
use daken/fixture/output_builder as ob

const fee_partial = taker_fee_partial + maker_fee_partial

const fee_full = taker_fee_full + maker_fee_full

fn run(
  fills: List<Fill>,
  inputs: List<Input>,
  refs: List<Input>,
  outputs: List<Output>,
  fee_val: Value,
) -> Bool {
  sell.verify(
    fixture.bid_skh,
    fixture.config(),
    [(0, fills)],
    inputs,
    refs,
    outputs,
    fee_val,
    fixture.tx_start(),
  )
}

fn refs_token() -> List<Input> {
  [
    fixture.pool_ref(0, fixture.supply_maturity()),
    fixture.config_ref(1, fixture.config()),
  ]
}

fn refs_ada() -> List<Input> {
  [
    fixture.pool_ref_ada(0, fixture.supply_maturity()),
    fixture.config_ref(1, fixture.config()),
  ]
}

// ------------------------------------------------------------- the happy path

/// A1 — partial fill, origin a token other than ADA.
test a1_partial_token_origin() {
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: 1 }],
    [fixture.bid_in(0, alice_vk, yield, bid_amount)],
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.cont_out(alice_vk, yield, bid_left_partial),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// A2 — partial fill, origin is ADA. The order's money and the min-UTxO share one
/// field.
test a2_partial_ada_origin() {
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: 1 }],
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    refs_ada(),
    [
      fixture.payout_out_ada(alice_vk, pt_partial, min_ada),
      fixture.cont_out_ada(alice_vk, yield, bid_left_partial),
      fixture.fee_out_ada(fee_partial + min_ada),
    ],
    fixture.fee_value_ada(fee_partial + min_ada),
  )
}

/// A3 — full fill, origin is ADA. bid_left = 0, so the reserve must return to the
/// owner through the PT output itself, summed and compared ONCE.
test a3_full_ada_origin() {
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }],
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    refs_ada(),
    [
      fixture.payout_out_ada(alice_vk, pt_full, reserve),
      fixture.fee_out_ada(fee_full + min_ada),
    ],
    fixture.fee_value_ada(fee_full + min_ada),
  )
}

/// A4 — full fill, origin other than ADA.
test a4_full_token_origin() {
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }],
    [fixture.bid_in(0, alice_vk, yield, bid_amount)],
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_full, 0, min_ada),
      fixture.fee_out(fee_full),
    ],
    fixture.fee_value(fee_full),
  )
}

/// A5 — two people's orders in one transaction, indices increasing strictly.
test a5_two_orders() {
  run(
    [
      Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: 1 },
      Fill { order_in_idx: 1, owner_ou_idx: 2, cont_ou_idx: 3 },
    ],
    [
      fixture.bid_in(0, alice_vk, yield, bid_amount),
      fixture.bid_in(1, bob_vk, yield, bid_amount),
    ],
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.cont_out(alice_vk, yield, bid_left_partial),
      fixture.payout_out(bob_vk, pt_partial, 0, min_ada),
      fixture.cont_out(bob_vk, yield, bid_left_partial),
      fixture.fee_out(fee_partial * 2),
    ],
    fixture.fee_value(fee_partial * 2),
  )
}

// ------------------------------------------------------------- bid-specific

/// B1 — excess tokens on the order UTxO must return to the owner on a full fill.
/// Without `origin_reserve` the taker pockets this 500_000_000.
test b1_origin_surplus_returned() {
  let surplus = 500_000_000
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }],
    [
      fixture.bid_in_of(
        0,
        alice_vk,
        yield,
        bid_amount,
        bid_amount + surplus,
        min_ada,
      ),
    ],
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_full, surplus, min_ada),
      fixture.fee_out(fee_full),
    ],
    fixture.fee_value(fee_full),
  )
}

/// B2 — the same scenario, with the taker keeping the excess.
test b2_origin_surplus_stolen() fail {
  let surplus = 500_000_000
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }],
    [
      fixture.bid_in_of(
        0,
        alice_vk,
        yield,
        bid_amount,
        bid_amount + surplus,
        min_ada,
      ),
    ],
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_full, 0, min_ada),
      fixture.fee_out(fee_full),
    ],
    fixture.fee_value(fee_full),
  )
}

/// B3 — griefing: 2 PT for a cash_out of 1, closing out a 1000 ADA order
/// entirely. The dust threshold on the full-fill branch stops it.
test b3_dust_grief_on_full_fill() fail {
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }],
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    refs_ada(),
    [
      fixture.payout_out_ada(alice_vk, 2, bid_amount + reserve),
      fixture.fee_out_ada(min_ada),
    ],
    fixture.fee_value_ada(min_ada),
  )
}

/// B4 — a remainder below `min_borrow_amount` may not build a continuation.
///
/// `pt = 1_030_000_000` gives `cash_out = 995_249_404`, under `bid_amount`, and
/// `bid_left = 4_750_596 < min_borrow`, so the dust threshold on the
/// continuation branch is what blocks it.
test b4_dust_remainder_on_continuation() fail {
  run(
    one_fill(),
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    refs_ada(),
    [
      fixture.payout_out_ada(alice_vk, 1_030_000_000, min_ada),
      fixture.cont_out_ada(alice_vk, yield, 4_750_596),
      fixture.fee_out_ada(2_979_788 + min_ada),
    ],
    fixture.fee_value_ada(2_979_788 + min_ada),
  )
}

/// B5 — a remainder at or above min_borrow_amount may not be filled out.
test b5_full_fill_leaving_too_much() fail {
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }],
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    refs_ada(),
    [
      fixture.payout_out_ada(alice_vk, pt_partial, bid_left_partial + reserve),
      fixture.fee_out_ada(fee_partial + min_ada),
    ],
    fixture.fee_value_ada(fee_partial + min_ada),
  )
}

/// B6 — the continuation does not keep the reserve: the taker drains the owner's
/// padding ADA.
test b6_continuation_skims_reserve() fail {
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: 1 }],
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    refs_ada(),
    [
      fixture.payout_out_ada(alice_vk, pt_partial, min_ada),
      fixture.cont_out_ada_of(
        alice_vk,
        yield,
        bid_left_partial,
        bid_left_partial,
      ),
      fixture.fee_out_ada(fee_partial + min_ada),
    ],
    fixture.fee_value_ada(fee_partial + min_ada),
  )
}

/// B7 — the order UTxO carries a foreign token while the origin is ADA.
test b7_junk_token_in_ada_order() fail {
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }],
    [fixture.bid_in_of(0, alice_vk, yield, bid_amount, 1, bid_amount + reserve)],
    refs_ada(),
    [
      fixture.payout_out_ada(alice_vk, pt_full, reserve),
      fixture.fee_out_ada(fee_full + min_ada),
    ],
    fixture.fee_value_ada(fee_full + min_ada),
  )
}

/// B8 — the pool has matured, everything else built correctly.
///
/// `duration = 0` so `price = pt`. `pt = 998_003_992` gives a `cash_out` of
/// 999_999_999, just under `bid_amount`, and `bid_left = 1 < min_borrow`, so the
/// full-fill branch is otherwise legitimate. What blocks it is `duration > 0`.
test b8_matured_pool() fail {
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }],
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    [
      fixture.pool_ref_ada(0, fixture.tx_start()),
      fixture.config_ref(1, fixture.config()),
    ],
    [
      fixture.payout_out_ada(alice_vk, 998_003_992, reserve + 1),
      fixture.fee_out_ada(2_994_011 + min_ada),
    ],
    fixture.fee_value_ada(2_994_011 + min_ada),
  )
}

// ------------------------------------------------------------- theft attempts

fn partial_ok() -> List<Output> {
  [
    fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
    fixture.cont_out(alice_vk, yield, bid_left_partial),
    fixture.fee_out(fee_partial),
  ]
}

fn one_order() -> List<Input> {
  [fixture.bid_in(0, alice_vk, yield, bid_amount)]
}

fn one_fill() -> List<Fill> {
  [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: 1 }]
}

/// C1 — the PT output is missing the `bid_skh` tag.
test c1_payout_without_tag() fail {
  run(
    one_fill(),
    one_order(),
    refs_token(),
    [
      ob.new(fixture.payout_addr(alice_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(fixture.pool_pid, fixture.pt_tn(), pt_partial),
      fixture.cont_out(alice_vk, yield, bid_left_partial),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// C3 — two fills sharing one PT output.
test c3_owner_out_shared() fail {
  run(
    [
      Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: 1 },
      Fill { order_in_idx: 1, owner_ou_idx: 0, cont_ou_idx: 2 },
    ],
    [
      fixture.bid_in(0, alice_vk, yield, bid_amount),
      fixture.bid_in(1, alice_vk, yield, bid_amount),
    ],
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.cont_out(alice_vk, yield, bid_left_partial),
      fixture.cont_out(alice_vk, yield, bid_left_partial),
      fixture.fee_out(fee_partial * 2),
    ],
    fixture.fee_value(fee_partial * 2),
  )
}

/// C4 — two fills sharing one continuation.
test c4_cont_out_shared() fail {
  run(
    [
      Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: 2 },
      Fill { order_in_idx: 1, owner_ou_idx: 1, cont_ou_idx: 2 },
    ],
    [
      fixture.bid_in(0, alice_vk, yield, bid_amount),
      fixture.bid_in(1, alice_vk, yield, bid_amount),
    ],
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.cont_out(alice_vk, yield, bid_left_partial),
      fixture.fee_out(fee_partial * 2),
    ],
    fixture.fee_value(fee_partial * 2),
  )
}

/// C5 — one order appearing twice in the fill list.
test c5_same_order_twice() fail {
  run(
    [
      Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: 1 },
      Fill { order_in_idx: 0, owner_ou_idx: 2, cont_ou_idx: 3 },
    ],
    one_order(),
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.cont_out(alice_vk, yield, bid_left_partial),
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.cont_out(alice_vk, yield, bid_left_partial),
      fixture.fee_out(fee_partial * 2),
    ],
    fixture.fee_value(fee_partial * 2),
  )
}

/// C6 — an empty group list: if withdraw passes clean, anyone can sweep the
/// reward account.
test c6_no_pool_fills() fail {
  sell.verify(
    fixture.bid_skh,
    fixture.config(),
    [],
    one_order(),
    refs_token(),
    partial_ok(),
    fixture.fee_value(fee_partial),
    fixture.tx_start(),
  )
}

/// C7 — a group with a pool but no fills: the same hole in another shape.
test c7_empty_group() fail {
  sell.verify(
    fixture.bid_skh,
    fixture.config(),
    [(0, [])],
    one_order(),
    refs_token(),
    partial_ok(),
    fixture.fee_value(fee_partial),
    fixture.tx_start(),
  )
}

/// C8 — the fee is underpaid.
test c8_fee_short() fail {
  run(
    one_fill(),
    one_order(),
    refs_token(),
    partial_ok(),
    fixture.fee_value(fee_partial - 1),
  )
}

/// C9 — `offered_yield = 0`, with the continuation built correctly for that very
/// rate, so `offered_yield > 0` is the only thing that blocks it. A zero yield
/// discounts nothing: `price = pt`, `cash_out = 501_000_000`,
/// `bid_left = 499_000_000`.
test c9_non_positive_yield() fail {
  run(
    one_fill(),
    [fixture.bid_in(0, alice_vk, 0, bid_amount)],
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.cont_out_of(alice_vk, 0, 499_000_000, 499_000_000, min_ada),
      fixture.fee_out(1_500_000),
    ],
    fixture.fee_value(1_500_000),
  )
}

/// C10 — the continuation changes yield: the owner is forced onto another rate.
test c10_continuation_changes_yield() fail {
  run(
    one_fill(),
    one_order(),
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.cont_out(alice_vk, yield + 500, bid_left_partial),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// C11 — the continuation changes owner.
test c11_continuation_changes_owner() fail {
  run(
    one_fill(),
    one_order(),
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.cont_out(bob_vk, yield, bid_left_partial),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// C12 — the continuation carries a different stake credential: the order can
/// still be filled but falls outside the address whose delegation the owner
/// controls.
test c12_continuation_changes_stake() fail {
  run(
    one_fill(),
    one_order(),
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      ob.new(fixture.order_addr(bob_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(fixture.origin_pid, fixture.origin_tn, bid_left_partial)
        |> ob.add_inline_datum(
            fixture.datum_of(alice_vk, yield, bid_left_partial),
          ),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// C13 — the PT output goes to an address other than the owner's.
test c13_payout_to_wrong_address() fail {
  run(
    one_fill(),
    one_order(),
    refs_token(),
    [
      fixture.payout_out(bob_vk, pt_partial, 0, min_ada),
      fixture.cont_out(alice_vk, yield, bid_left_partial),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// C14 — a self-made pool reference input at a wallet address, carrying a token
/// named like the pool NFT.
test c14_fake_pool_ref() fail {
  run(
    one_fill(),
    one_order(),
    [
      Input {
        output_reference: fixture.out_ref(9),
        output: ob.new(fixture.wallet_addr(bob_vk))
          |> ob.add_lovelace(min_ada)
          |> ob.add_asset(fixture.pool_pid, fixture.pool_id, 1)
          |> ob.add_inline_datum(fixture.datum_of(alice_vk, yield, bid_amount)),
      },
      fixture.config_ref(1, fixture.config()),
    ],
    partial_ok(),
    fixture.fee_value(fee_partial),
  )
}

/// C15 — the pool's policy is outside the allowlist.
test c15_policy_not_allowed() fail {
  sell.verify(
    fixture.bid_skh,
    ExchangeConfig { ..fixture.config(), pt_policies: [fixture.junk_pid] },
    [(0, one_fill())],
    one_order(),
    refs_token(),
    partial_ok(),
    fixture.fee_value(fee_partial),
    fixture.tx_start(),
  )
}

/// C16 — the datum points at another pool's PT, with EVERY output built
/// consistently for that datum.
///
/// Every output is built consistently for that datum, so `pt_tn == pool.pt_tn`
/// is the only thing that blocks it. The second angle on one constraint: `f7`
/// attacks from the pool reference input, `c16` from the datum.
test c16_pt_asset_wrong_pool() fail {
  let wrong =
    BidDatum {
      owner_vk: alice_vk,
      pt_asset: (fixture.pool_pid, fixture.pt_tn2()),
      offered_yield: yield,
      bid_amount,
    }
  run(
    one_fill(),
    [
      Input {
        output_reference: fixture.out_ref(0),
        output: ob.new(fixture.order_addr(alice_vk))
          |> ob.add_lovelace(min_ada)
          |> ob.add_asset(fixture.origin_pid, fixture.origin_tn, bid_amount)
          |> ob.add_inline_datum(wrong),
      },
    ],
    refs_token(),
    [
      ob.new(fixture.payout_addr(alice_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(fixture.pool_pid, fixture.pt_tn2(), pt_partial)
        |> ob.add_inline_datum(fixture.bid_skh),
      ob.new(fixture.order_addr(alice_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(fixture.origin_pid, fixture.origin_tn, bid_left_partial)
        |> ob.add_inline_datum(
            BidDatum { ..wrong, bid_amount: bid_left_partial },
          ),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// C17 — the fee ceiling is hard-coded, not read from config. The fee is paid in
/// full at the over-ceiling rate, so only `seller_fee <= max_fee_rate` blocks it.
test c17_fee_rate_above_cap() fail {
  run_cfg(
    ExchangeConfig { ..fixture.config(), seller_fee: 501 },
    [(0, one_fill())],
    one_order(),
    refs_token(),
    partial_ok(),
    fixture.fee_value(24_156_539 + maker_fee_partial),
  )
}

// ------------------------------------------ money-conservation constraints

/// The PT amount that leaves change just under the dust threshold: the only
/// full-fill scenario with `cash_back > 0`, so the "return the change" half of
/// the output rule is exercised.
const pt_cash_back = 1_025_602_223

const cash_back_amt = 8_999_999

const fee_cash_back = 1_978_043 + 989_022

/// The next PT amount up, leaving exactly `min_borrow_amount`.
const pt_at_min_borrow = 1_025_602_222

const other_skh = #"0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c"

fn run_cfg(
  cfg: ExchangeConfig,
  groups: List<(Int, List<Fill>)>,
  inputs: List<Input>,
  refs: List<Input>,
  outputs: List<Output>,
  fee_val: assets.Value,
) -> Bool {
  sell.verify(
    fixture.bid_skh,
    cfg,
    groups,
    inputs,
    refs,
    outputs,
    fee_val,
    fixture.tx_start(),
  )
}

/// F1 — a full fill that still leaves change: the owner gets BOTH the change and
/// the reserve back through the PT output itself, summed and compared once.
test f1_full_fill_returns_cash_back() {
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }],
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    refs_ada(),
    [
      fixture.payout_out_ada(alice_vk, pt_cash_back, cash_back_amt + reserve),
      fixture.fee_out_ada(fee_cash_back + min_ada),
    ],
    fixture.fee_value_ada(fee_cash_back + min_ada),
  )
}

/// F2 — the same, with the taker keeping the change.
test f2_full_fill_withholds_cash_back() fail {
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }],
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    refs_ada(),
    [
      fixture.payout_out_ada(alice_vk, pt_cash_back, reserve),
      fixture.fee_out_ada(fee_cash_back + min_ada),
    ],
    fixture.fee_value_ada(fee_cash_back + min_ada),
  )
}

/// F3 — the same, with the taker paying the change in full but swallowing the
/// reserve. Two separate comparisons let it through; summing and comparing once
/// does not.
test f3_full_fill_swallows_reserve() fail {
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }],
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    refs_ada(),
    [
      fixture.payout_out_ada(alice_vk, pt_cash_back, cash_back_amt),
      fixture.fee_out_ada(fee_cash_back + min_ada),
    ],
    fixture.fee_value_ada(fee_cash_back + min_ada),
  )
}

/// F4 — a remainder exactly equal to `min_borrow_amount` must go through the
/// continuation.
test f4_remainder_exactly_min_borrow_continues() {
  run(
    one_fill(),
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    refs_ada(),
    [
      fixture.payout_out_ada(alice_vk, pt_at_min_borrow, min_ada),
      fixture.cont_out_ada(alice_vk, yield, min_borrow),
      fixture.fee_out_ada(fee_cash_back + min_ada),
    ],
    fixture.fee_value_ada(fee_cash_back + min_ada),
  )
}

/// F5 — delivering more PT than the order's money reaches. A negative `bid_left`
/// drops the output condition on the full-fill branch below even `reserve`.
test f5_cash_out_exceeds_bid_amount() fail {
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }],
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    refs_ada(),
    [
      fixture.payout_out_ada(alice_vk, 1_035_951_386, 1_000_000),
      fixture.fee_out_ada(2_997_005 + min_ada),
    ],
    fixture.fee_value_ada(2_997_005 + min_ada),
  )
}

/// F6 — the datum tag on the PT output CARRIES THE WRONG VALUE. This is the
/// constraint the design leans on to let Ask and Bid share one transaction. `c1`
/// drops the datum entirely and so fails at `expect InlineDatum`, not at the tag
/// comparison.
test f6_payout_tagged_with_other_generation() fail {
  run(
    one_fill(),
    one_order(),
    refs_token(),
    [
      ob.new(fixture.payout_addr(alice_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(fixture.pool_pid, fixture.pt_tn(), pt_partial)
        |> ob.add_inline_datum(other_skh),
      fixture.cont_out(alice_vk, yield, bid_left_partial),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// F7 — the fill group points at a pool of the SAME POLICY but closer to
/// maturity. `duration` shrinks so `price` nears face value: the owner pays the
/// same money and receives 998_003_992 PT instead of 1_034_916_470 — losing 3.6%
/// of the order's value.
test f7_pool_ref_of_another_market() fail {
  run_cfg(
    fixture.config(),
    [(1, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    [
      fixture.pool_ref_ada(0, fixture.supply_maturity()),
      fixture.pool_ref_of(
        1,
        fixture.tx_start() + 1,
        fixture.pool_pid,
        fixture.pool_id2,
        ("", ""),
      ),
    ],
    [
      fixture.payout_out_ada(alice_vk, 998_003_992, reserve + 3),
      fixture.fee_out_ada(2_994_011 + min_ada),
    ],
    fixture.fee_value_ada(2_994_011 + min_ada),
  )
}

/// F8 — a non-ADA continuation holding exactly 1 unit of origin while the datum
/// declares `bid_amount = 516_869_222`. `b6` exercises the ADA branch only.
test f8_token_continuation_holds_no_money() fail {
  run(
    one_fill(),
    one_order(),
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.cont_out_of(alice_vk, yield, bid_left_partial, 1, min_ada),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// F9 — the non-ADA continuation has its padding ADA drawn down.
test f9_token_continuation_skims_ada() fail {
  run(
    one_fill(),
    one_order(),
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.cont_out_of(
        alice_vk,
        yield,
        bid_left_partial,
        bid_left_partial,
        min_ada - 1,
      ),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// F10 — a NEGATIVE fee. Config is mutable and whoever holds the license NFT can
/// set a negative rate, at which point `fee_owed` carries a negative entry and
/// `value_covers` is satisfied even by an empty fee output.
test f10_negative_fee_rate_skips_fee() fail {
  run_cfg(
    ExchangeConfig { ..fixture.config(), buyer_fee: -20 },
    [(0, one_fill())],
    one_order(),
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.cont_out(alice_vk, yield, 518_797_887),
      fixture.fee_out(0),
    ],
    fixture.fee_value(0),
  )
}

/// F11 — the fee ceiling on the BUY side, with the fee paid in full at the
/// over-ceiling rate. `c17` tries `seller_fee` only, and underpays as well, so it
/// fails at `value_covers` instead.
test f11_buyer_fee_above_cap() fail {
  run_cfg(
    ExchangeConfig { ..fixture.config(), buyer_fee: 501 },
    [(0, one_fill())],
    one_order(),
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.cont_out(alice_vk, yield, 493_677_016),
      fixture.fee_out(24_156_538 + 482_167),
    ],
    fixture.fee_value(24_156_538 + 482_167),
  )
}

/// F12 — the order UTxO sits at a wallet address rather than at the script.
test f12_order_input_not_at_script() fail {
  run(
    [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }],
    [
      Input {
        output_reference: fixture.out_ref(0),
        output: ob.new(fixture.payout_addr(alice_vk))
          |> ob.add_lovelace(min_ada)
          |> ob.add_asset(fixture.origin_pid, fixture.origin_tn, bid_amount)
          |> ob.add_inline_datum(fixture.datum_of(alice_vk, yield, bid_amount)),
      },
    ],
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_full, 0, min_ada),
      fixture.fee_out(fee_full),
    ],
    fixture.fee_value(fee_full),
  )
}

/// F13 — the order UTxO carries a reference script.
test f13_order_input_has_reference_script() fail {
  run(
    one_fill(),
    [
      Input {
        output_reference: fixture.out_ref(0),
        output: ob.new(fixture.order_addr(alice_vk))
          |> ob.add_lovelace(min_ada)
          |> ob.add_asset(fixture.origin_pid, fixture.origin_tn, bid_amount)
          |> ob.add_inline_datum(fixture.datum_of(alice_vk, yield, bid_amount))
          |> ob.add_reference_script(other_skh),
      },
    ],
    refs_token(),
    partial_ok(),
    fixture.fee_value(fee_partial),
  )
}

/// F14 — origin is ADA, and the order UTxO holds less lovelace than the datum's
/// `bid_amount`.
test f14_ada_order_underfunded() fail {
  run(
    one_fill(),
    [fixture.bid_in_ada_of(0, alice_vk, yield, bid_amount, bid_amount - 1)],
    refs_ada(),
    [
      fixture.payout_out_ada(alice_vk, pt_partial, min_ada),
      fixture.cont_out_ada(alice_vk, yield, bid_left_partial),
      fixture.fee_out_ada(fee_partial + min_ada),
    ],
    fixture.fee_value_ada(fee_partial + min_ada),
  )
}

/// F15 — origin other than ADA, and the order UTxO holds fewer tokens than
/// `bid_amount`.
test f15_token_order_underfunded() fail {
  run(
    one_fill(),
    [fixture.bid_in_of(0, alice_vk, yield, bid_amount, bid_amount - 1, min_ada)],
    refs_token(),
    partial_ok(),
    fixture.fee_value(fee_partial),
  )
}

/// F16 — the order UTxO holds a token that is NOT the pool's origin token.
test f16_order_holds_wrong_token() fail {
  run(
    one_fill(),
    [
      Input {
        output_reference: fixture.out_ref(0),
        output: ob.new(fixture.order_addr(alice_vk))
          |> ob.add_lovelace(min_ada)
          |> ob.add_asset(other_skh, fixture.origin_tn, bid_amount)
          |> ob.add_inline_datum(fixture.datum_of(alice_vk, yield, bid_amount)),
      },
    ],
    refs_token(),
    partial_ok(),
    fixture.fee_value(fee_partial),
  )
}

/// F17 — the continuation carries a reference script: the remainder order can no
/// longer be filled and the owner is left with nothing but cancelling.
test f17_continuation_has_reference_script() fail {
  run(
    one_fill(),
    one_order(),
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      ob.new(fixture.order_addr(alice_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(fixture.origin_pid, fixture.origin_tn, bid_left_partial)
        |> ob.add_inline_datum(
            fixture.datum_of(alice_vk, yield, bid_left_partial),
          )
        |> ob.add_reference_script(other_skh),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// F18 — output giao PT mang reference script.
test f18_payout_has_reference_script() fail {
  run(
    one_fill(),
    one_order(),
    refs_token(),
    [
      ob.new(fixture.payout_addr(alice_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(fixture.pool_pid, fixture.pt_tn(), pt_partial)
        |> ob.add_inline_datum(fixture.bid_skh)
        |> ob.add_reference_script(other_skh),
      fixture.cont_out(alice_vk, yield, bid_left_partial),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// F19 — the continuation of an ADA order carrying a foreign token: the order is
/// sealed shut.
test f19_ada_continuation_carries_junk() fail {
  run(
    one_fill(),
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    refs_ada(),
    [
      fixture.payout_out_ada(alice_vk, pt_partial, min_ada),
      ob.new(fixture.order_addr(alice_vk))
        |> ob.add_lovelace(bid_left_partial + reserve)
        |> ob.add_asset(fixture.origin_pid, fixture.origin_tn, 1)
        |> ob.add_inline_datum(
            fixture.datum_of(alice_vk, yield, bid_left_partial),
          ),
      fixture.fee_out_ada(fee_partial + min_ada),
    ],
    fixture.fee_value_ada(fee_partial + min_ada),
  )
}

/// F20 — the continuation of a non-ADA order carrying a third token.
test f20_token_continuation_carries_junk() fail {
  run(
    one_fill(),
    one_order(),
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      ob.new(fixture.order_addr(alice_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(fixture.origin_pid, fixture.origin_tn, bid_left_partial)
        |> ob.add_asset(other_skh, fixture.origin_tn, 1)
        |> ob.add_inline_datum(
            fixture.datum_of(alice_vk, yield, bid_left_partial),
          ),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// B17 — origin other than ADA, a PARTIAL fill of an order carrying excess
/// tokens. The excess stays in the continuation; the PT output carries nothing
/// extra.
test b17_token_surplus_stays_in_continuation() {
  let surplus = 500_000_000
  run(
    one_fill(),
    [
      fixture.bid_in_of(
        0,
        alice_vk,
        yield,
        bid_amount,
        bid_amount + surplus,
        min_ada,
      ),
    ],
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.cont_out_of(
        alice_vk,
        yield,
        bid_left_partial,
        bid_left_partial + surplus,
        min_ada,
      ),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// B18 — the same, with the continuation forgetting the excess.
test b18_token_surplus_dropped_from_continuation() fail {
  let surplus = 500_000_000
  run(
    one_fill(),
    [
      fixture.bid_in_of(
        0,
        alice_vk,
        yield,
        bid_amount,
        bid_amount + surplus,
        min_ada,
      ),
    ],
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      fixture.cont_out(alice_vk, yield, bid_left_partial),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// F21 — the datum points at a PT of the right NAME but a different POLICY from
/// the pool reference input, with every output built consistently for that
/// policy. Name and policy are separate constraints: the name follows from
/// `pool_id`, the policy from the pool's address, so a foreign policy can still
/// produce the right name.
test f21_pt_policy_wrong_pool() fail {
  let wrong =
    BidDatum {
      owner_vk: alice_vk,
      pt_asset: (other_skh, fixture.pt_tn()),
      offered_yield: yield,
      bid_amount,
    }
  run(
    one_fill(),
    [
      Input {
        output_reference: fixture.out_ref(0),
        output: ob.new(fixture.order_addr(alice_vk))
          |> ob.add_lovelace(min_ada)
          |> ob.add_asset(fixture.origin_pid, fixture.origin_tn, bid_amount)
          |> ob.add_inline_datum(wrong),
      },
    ],
    refs_token(),
    [
      ob.new(fixture.payout_addr(alice_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(other_skh, fixture.pt_tn(), pt_partial)
        |> ob.add_inline_datum(fixture.bid_skh),
      ob.new(fixture.order_addr(alice_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(fixture.origin_pid, fixture.origin_tn, bid_left_partial)
        |> ob.add_inline_datum(
            BidDatum { ..wrong, bid_amount: bid_left_partial },
          ),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// F22 — the order UTxO holds a token of the origin's right POLICY but the wrong
/// NAME. `f16` changes only the policy, so the name comparison was never tried.
test f22_order_holds_wrong_token_name() fail {
  run(
    one_fill(),
    [
      Input {
        output_reference: fixture.out_ref(0),
        output: ob.new(fixture.order_addr(alice_vk))
          |> ob.add_lovelace(min_ada)
          |> ob.add_asset(fixture.origin_pid, #"ffff", bid_amount)
          |> ob.add_inline_datum(fixture.datum_of(alice_vk, yield, bid_amount)),
      },
    ],
    refs_token(),
    partial_ok(),
    fixture.fee_value(fee_partial),
  )
}

/// F23 — delivering exactly 1 PT: FLOOR takes the price to 0, so the taker moves
/// the order to a new UTxO without paying anything. The opposite of ask_limit,
/// where CEIL always gives one unit a price.
test f23_one_pt_prices_to_zero() fail {
  run(
    one_fill(),
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    refs_ada(),
    [
      fixture.payout_out_ada(alice_vk, 1, min_ada),
      fixture.cont_out_ada(alice_vk, yield, bid_amount),
      fixture.fee_out_ada(min_ada),
    ],
    fixture.fee_value_ada(min_ada),
  )
}

/// F24 — a fixed point: a pool declaring its origin token to BE its own PT. The
/// same token quantity on an output counts both as PT delivered and as money
/// returned.
///
/// Unreachable under the current allowlist, where the pool contract requires the
/// supply token to be in `deposit_supported`, but one line is cheaper than an
/// argument.
test f24_origin_token_is_pt() fail {
  let pt = (fixture.pool_pid, fixture.pt_tn())
  run_cfg(
    fixture.config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    [
      Input {
        output_reference: fixture.out_ref(0),
        output: ob.new(fixture.order_addr(alice_vk))
          |> ob.add_lovelace(min_ada)
          |> ob.add_asset(fixture.pool_pid, fixture.pt_tn(), bid_amount)
          |> ob.add_inline_datum(fixture.datum_of(alice_vk, yield, bid_amount)),
      },
    ],
    [
      fixture.pool_ref_of(
        0,
        fixture.supply_maturity(),
        fixture.pool_pid,
        fixture.pool_id,
        pt,
      ),
      fixture.config_ref(1, fixture.config()),
    ],
    [
      ob.new(fixture.payout_addr(alice_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(fixture.pool_pid, fixture.pt_tn(), pt_full)
        |> ob.add_inline_datum(fixture.bid_skh),
      ob.new(fixture.wallet_addr(fixture.fee_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(fixture.pool_pid, fixture.pt_tn(), fee_full)
        |> ob.add_inline_datum(fixture.bid_skh),
    ],
    assets.from_lovelace(min_ada)
      |> assets.add(fixture.pool_pid, fixture.pt_tn(), fee_full),
  )
}

/// F25 — a negative fee on the SELL side. `f10` tries only the buy side; the two
/// fee rates are two separate constraints.
test f25_negative_seller_fee() fail {
  run_cfg(
    ExchangeConfig { ..fixture.config(), seller_fee: -10 },
    [(0, one_fill())],
    one_order(),
    refs_token(),
    partial_ok(),
    fixture.fee_value(fee_partial),
  )
}

/// F26 — the continuation holds EXACTLY ONE token in the right quantity, but of
/// another POLICY. `single_token_of` lets it through (still one token), so only
/// the policy comparison blocks it. `f20` stuffs in a third token and so fails
/// at `single_token_of` instead.
test f26_continuation_holds_wrong_policy() fail {
  run(
    one_fill(),
    one_order(),
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      ob.new(fixture.order_addr(alice_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(other_skh, fixture.origin_tn, bid_left_partial)
        |> ob.add_inline_datum(
            fixture.datum_of(alice_vk, yield, bid_left_partial),
          ),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}

/// F27 — the same, but with the right policy and the wrong token NAME.
test f27_continuation_holds_wrong_token_name() fail {
  run(
    one_fill(),
    one_order(),
    refs_token(),
    [
      fixture.payout_out(alice_vk, pt_partial, 0, min_ada),
      ob.new(fixture.order_addr(alice_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(fixture.origin_pid, #"ffff", bid_left_partial)
        |> ob.add_inline_datum(
            fixture.datum_of(alice_vk, yield, bid_left_partial),
          ),
      fixture.fee_out(fee_partial),
    ],
    fixture.fee_value(fee_partial),
  )
}
