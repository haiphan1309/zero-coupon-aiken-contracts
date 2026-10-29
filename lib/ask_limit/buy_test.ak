//// Transaction-level tests for the Buy branch.
////
//// Group B: the correct path, which must PASS.
//// Group A: built wrong in order to steal, which must FAIL — via `test ... fail`.
////
//// All of them call `buy.verify` directly and pass `tx_end()` explicitly, to
//// separate the money arithmetic from the handling of the validity range. The
//// time side has its own tests at the `sc_ask_limit.withdraw` level.

use ask_limit/ask_types.{AskDatum, ExchangeConfig, Fill}
use ask_limit/buy
use ask_limit/fixture.{
  alice_vk, ask_skh, bob_vk, config, config_ref, cont_out, duration, fee_value,
  order_in, payout_out, pool_ref, supply_maturity, tx_end,
}
use ask_limit/price
use cardano/address.{Address, Inline, VerificationKey}
use cardano/assets
use cardano/transaction.{InlineDatum, Input, Output}

// Figures from the worked example
const price_alice = 964_332_893

const s_fee_alice = 964_332

const b_fee_alice = 1_928_666

const price_bob = 191_500_525

const s_fee_bob = 191_500

const b_fee_bob = 383_002

// ------------------------------------------------------------------ group B

/// B1 — one order, bought out, origin an ordinary token.
/// The seller receives the sale proceeds plus the min ADA locked in the order
/// UTxO.
test b1_single_full_fill() {
  let inputs = [order_in(0, alice_vk, 1_500, 1_000_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
      fixture.fee_out(s_fee_alice + b_fee_alice),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    fee_value(s_fee_alice + b_fee_alice),
    tx_end(),
  )
}

/// B3 — one order, a partial buy, the rest staying in the new order.
/// The min ADA stays with the remainder, so the seller is NOT refunded it.
test b3_single_partial_fill() {
  let inputs = [order_in(0, bob_vk, 1_800, 500_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      payout_out(bob_vk, price_bob - s_fee_bob, 0),
      cont_out(bob_vk, 1_800, 300_000_000),
      fixture.fee_out(s_fee_bob + b_fee_bob),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: 1 }])],
    inputs,
    refs,
    outputs,
    fee_value(s_fee_bob + b_fee_bob),
    tx_end(),
  )
}

/// B4 — the worked example itself: two orders on the same pool, one bought out
/// and one partial, sharing a single pool reference input.
test b4_two_fills_one_pool() {
  let inputs =
    [
      order_in(0, alice_vk, 1_500, 1_000_000_000),
      order_in(1, bob_vk, 1_800, 500_000_000),
    ]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let total_fee = s_fee_alice + b_fee_alice + s_fee_bob + b_fee_bob
  let outputs =
    [
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
      payout_out(bob_vk, price_bob - s_fee_bob, 0),
      cont_out(bob_vk, 1_800, 300_000_000),
      fixture.fee_out(total_fee),
    ]
  buy.verify(
    ask_skh,
    config(),
    [
      (
        0,
        [
          Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 },
          Fill { order_in_idx: 1, owner_ou_idx: 1, cont_ou_idx: 2 },
        ],
      ),
    ],
    inputs,
    refs,
    outputs,
    fee_value(total_fee),
    tx_end(),
  )
}

/// B10 — a pool past maturity gives duration = 0 and PT at face value.
test b10_matured_pool_pays_par() {
  let pt = 1_000_000_000
  let s_fee = price.seller_fee_of(pt, 10)
  let b_fee = price.buyer_fee_of(pt, 20)
  let inputs = [order_in(0, alice_vk, 1_500, pt)]
  let refs = [pool_ref(0, tx_end() - 1), config_ref(1, config())]
  let outputs =
    [
      payout_out(alice_vk, pt - s_fee, fixture.min_ada),
      fixture.fee_out(s_fee + b_fee),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    fee_value(s_fee + b_fee),
    tx_end(),
  )
}

// ------------------------------------------------------------------ group A

/// A1 — two fills pointing at one payout output.
/// Same seller, so the addresses match; the output then only has to cover the
/// larger fill rather than the sum of both. Blocked by requiring owner_ou_idx to
/// increase strictly.
test a1_shared_payout_output() fail {
  let inputs =
    [
      order_in(0, alice_vk, 1_500, 1_000_000_000),
      order_in(1, alice_vk, 1_500, 1_000_000_000),
    ]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada * 2),
      fixture.fee_out(( s_fee_alice + b_fee_alice ) * 2),
    ]
  buy.verify(
    ask_skh,
    config(),
    [
      (
        0,
        [
          Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 },
          Fill { order_in_idx: 1, owner_ou_idx: 0, cont_ou_idx: -1 },
        ],
      ),
    ],
    inputs,
    refs,
    outputs,
    fee_value(( s_fee_alice + b_fee_alice ) * 2),
    tx_end(),
  )
}

/// A9 — the remainder order has its locked ADA drawn down.
test a9_continuation_drains_ada() fail {
  let inputs = [order_in(0, bob_vk, 1_800, 500_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let drained =
    Output {
      ..cont_out(bob_vk, 1_800, 300_000_000),
      value: assets.from_lovelace(1_000_000)
        |> assets.add(fixture.pool_pid, fixture.pt_tn(), 300_000_000),
    }
  let outputs =
    [
      payout_out(bob_vk, price_bob - s_fee_bob, 0),
      drained,
      fixture.fee_out(s_fee_bob + b_fee_bob),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: 1 }])],
    inputs,
    refs,
    outputs,
    fee_value(s_fee_bob + b_fee_bob),
    tx_end(),
  )
}

/// A15 — the fee output is short.
test a15_underpaid_fee() fail {
  let inputs = [order_in(0, alice_vk, 1_500, 1_000_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
      fixture.fee_out(1),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    fee_value(1),
    tx_end(),
  )
}

/// A16 — config sets seller_fee to 100%, retroactively across every resting
/// order. Blocked by the hard 500 bp ceiling in the code.
test a16_fee_above_cap() fail {
  let bad = ExchangeConfig { ..config(), seller_fee: 10_000 }
  let inputs = [order_in(0, alice_vk, 1_500, 1_000_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, bad)]
  let outputs =
    [payout_out(alice_vk, 0, fixture.min_ada), fixture.fee_out(price_alice)]
  buy.verify(
    ask_skh,
    bad,
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    fee_value(price_alice),
    tx_end(),
  )
}

/// A20 — a partial buy leaving a remainder below the pool's min_borrow_amount.
test a20_dust_remainder() fail {
  let pt_left = fixture.min_borrow - 1
  let sold = 500_000_000 - pt_left
  let p = price.price_of(sold, 1_800, duration)
  let s = price.seller_fee_of(p, 10)
  let b = price.buyer_fee_of(p, 20)
  let inputs = [order_in(0, bob_vk, 1_800, 500_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      payout_out(bob_vk, p - s, 0),
      cont_out(bob_vk, 1_800, pt_left),
      fixture.fee_out(s + b),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: 1 }])],
    inputs,
    refs,
    outputs,
    fee_value(s + b),
    tx_end(),
  )
}

/// B2 — origin is ADA, bought out. The sale proceeds and the locked ADA share
/// one field, so they must be summed and compared once.
test b2_ada_origin_full_fill() {
  let inputs = [order_in(0, alice_vk, 1_500, 1_000_000_000)]
  let refs =
    [fixture.pool_ref_ada(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      fixture.payout_out_ada(
        alice_vk,
        price_alice - s_fee_alice + fixture.min_ada,
      ),
      fixture.fee_out_ada(s_fee_alice + b_fee_alice),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    fixture.fee_value_ada(s_fee_alice + b_fee_alice),
    tx_end(),
  )
}

/// B5 — two orders from two different pools: two groups, two reference inputs.
/// Same policy id, being the same deployment generation, differing only in asset
/// name.
test b5_two_pools_two_groups() {
  let inputs =
    [
      order_in(0, alice_vk, 1_500, 1_000_000_000),
      fixture.order_in_of(
        1,
        bob_vk,
        1_800,
        500_000_000,
        fixture.pool_pid,
        fixture.pt_tn2(),
      ),
    ]
  let refs =
    [
      pool_ref(0, supply_maturity()),
      fixture.pool_ref_of(
        1,
        supply_maturity(),
        fixture.pool_pid,
        fixture.pool_id2,
        fixture.origin_token(),
      ),
      config_ref(2, config()),
    ]
  let total_fee = s_fee_alice + b_fee_alice + s_fee_bob + b_fee_bob
  let outputs =
    [
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
      payout_out(bob_vk, price_bob - s_fee_bob, 0),
      fixture.cont_out_of(bob_vk, 1_800, 300_000_000, fixture.pt_tn2()),
      fixture.fee_out(total_fee),
    ]
  buy.verify(
    ask_skh,
    config(),
    [
      (0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }]),
      (1, [Fill { order_in_idx: 1, owner_ou_idx: 1, cont_ou_idx: 2 }]),
    ],
    inputs,
    refs,
    outputs,
    fee_value(total_fee),
    tx_end(),
  )
}

/// B6 — two orders from the SAME seller, each with its own output.
/// This is the price of the index constraint: they cannot be merged.
test b6_same_seller_two_outputs() {
  let inputs =
    [
      order_in(0, alice_vk, 1_500, 1_000_000_000),
      order_in(1, alice_vk, 1_500, 1_000_000_000),
    ]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let total_fee = ( s_fee_alice + b_fee_alice ) * 2
  let outputs =
    [
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
      fixture.fee_out(total_fee),
    ]
  buy.verify(
    ask_skh,
    config(),
    [
      (
        0,
        [
          Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 },
          Fill { order_in_idx: 1, owner_ou_idx: 1, cont_ou_idx: -1 },
        ],
      ),
    ],
    inputs,
    refs,
    outputs,
    fee_value(total_fee),
    tx_end(),
  )
}

/// B9 — zero fees both ways, and no fee output.
test b9_zero_fees() {
  let free = ExchangeConfig { ..config(), buyer_fee: 0, seller_fee: 0 }
  let inputs = [order_in(0, alice_vk, 1_500, 1_000_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, free)]
  let outputs = [payout_out(alice_vk, price_alice, fixture.min_ada)]
  buy.verify(
    ask_skh,
    free,
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    assets.zero,
    tx_end(),
  )
}

/// A2 — two fills pointing at one remainder output.
/// pt_sold is read from the output, so each fill computes its own small share,
/// the buyer pockets the difference and swallows one order's min ADA as well.
test a2_shared_continuation_output() fail {
  let inputs =
    [
      order_in(0, alice_vk, 1_800, 500_000_000),
      order_in(1, alice_vk, 1_800, 500_000_000),
    ]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      payout_out(alice_vk, price_bob - s_fee_bob, 0),
      payout_out(alice_vk, price_bob - s_fee_bob, 0),
      cont_out(alice_vk, 1_800, 300_000_000),
      fixture.fee_out(( s_fee_bob + b_fee_bob ) * 2),
    ]
  buy.verify(
    ask_skh,
    config(),
    [
      (
        0,
        [
          Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: 2 },
          Fill { order_in_idx: 1, owner_ou_idx: 1, cont_ou_idx: 2 },
        ],
      ),
    ],
    inputs,
    refs,
    outputs,
    fee_value(( s_fee_bob + b_fee_bob ) * 2),
    tx_end(),
  )
}

/// A3 — origin is ADA and the seller's output covers only the sale proceeds,
/// swallowing the order's min ADA. Checking the two conditions separately lets
/// it through, because both speak about the same lovelace field.
test a3_ada_origin_swallows_min_ada() fail {
  let inputs = [order_in(0, alice_vk, 1_500, 1_000_000_000)]
  let refs =
    [fixture.pool_ref_ada(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      fixture.payout_out_ada(alice_vk, price_alice - s_fee_alice),
      fixture.fee_out_ada(s_fee_alice + b_fee_alice),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    fixture.fee_value_ada(s_fee_alice + b_fee_alice),
    tx_end(),
  )
}

/// A7 — the remainder order changes owner in the datum.
///
/// The address must stay EXACTLY as it was, because `order_addr` embeds the
/// owner in the stake credential: change the address and the test blows up at
/// `cont_addr == order_addr` and never reaches the datum check, proving the
/// same thing as a10 rather than what it claims to prove.
test a7_continuation_changes_owner() fail {
  buy_partial_with_cont(
    Output {
      ..cont_out(alice_vk, 1_800, 300_000_000),
      datum: InlineDatum(AskDatum { owner_vk: bob_vk, requested_yield: 1_800 }),
    },
  )
}

/// A8 — the remainder order changes yield, the buyer discounting the next fill
/// for themselves.
test a8_continuation_changes_yield() fail {
  buy_partial_with_cont(cont_out(alice_vk, 1_400, 300_000_000))
}

/// A10 — the remainder order changes stake credential, and the buyer takes the
/// delegation rewards.
test a10_continuation_changes_stake() fail {
  buy_partial_with_cont(
    Output {
      ..cont_out(alice_vk, 1_800, 300_000_000),
      address: fixture.order_addr(bob_vk),
    },
  )
}

/// C4 — the remainder order carries a reference script.
test c4_continuation_has_reference_script() fail {
  buy_partial_with_cont(
    Output {
      ..cont_out(alice_vk, 1_800, 300_000_000),
      reference_script: Some(ask_skh),
    },
  )
}

/// A11 — paying to an address with the right payment key but somebody else's
/// stake.
test a11_payout_wrong_stake() fail {
  let inputs = [order_in(0, alice_vk, 1_500, 1_000_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  // Alice's payment key, Bob's stake — with payout_addr(bob_vk) both would be
  // wrong and the test would only prove "a different address fails".
  let wrong =
    Output {
      ..payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
      address: Address {
        payment_credential: VerificationKey(alice_vk),
        stake_credential: Some(Inline(VerificationKey(bob_vk))),
      },
    }
  let outputs = [wrong, fixture.fee_out(s_fee_alice + b_fee_alice)]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    fee_value(s_fee_alice + b_fee_alice),
    tx_end(),
  )
}

/// A12 — a self-made reference input at a wallet address, carrying a token
/// named like the pool NFT. The policy comes from the address's payment
/// credential, so it cannot be forged.
test a12_fake_pool_reference() fail {
  let inputs = [order_in(0, alice_vk, 1_500, 1_000_000_000)]
  let fake =
    Input {
      output_reference: fixture.out_ref(9),
      output: fixture.fake_pool_output(supply_maturity()),
    }
  let refs = [fake, config_ref(1, config())]
  let outputs =
    [
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
      fixture.fee_out(s_fee_alice + b_fee_alice),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    fee_value(s_fee_alice + b_fee_alice),
    tx_end(),
  )
}

/// A13 — PT of a policy outside the allowlist.
test a13_policy_not_in_allowlist() fail {
  let cfg = ExchangeConfig { ..config(), pt_policies: [fixture.junk_pid] }
  let inputs = [order_in(0, alice_vk, 1_500, 1_000_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, cfg)]
  let outputs =
    [
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
      fixture.fee_out(s_fee_alice + b_fee_alice),
    ]
  buy.verify(
    ask_skh,
    cfg,
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    fee_value(s_fee_alice + b_fee_alice),
    tx_end(),
  )
}

/// A14 — a fill sits in pool A's group while the order holds pool B's PT.
/// Unblocked, the buyer prices the PT against another pool's duration.
test a14_fill_points_at_wrong_pool() fail {
  let inputs =
    [
      fixture.order_in_of(
        0,
        alice_vk,
        1_500,
        1_000_000_000,
        fixture.pool_pid,
        fixture.pt_tn2(),
      ),
    ]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
      fixture.fee_out(s_fee_alice + b_fee_alice),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    fee_value(s_fee_alice + b_fee_alice),
    tx_end(),
  )
}

/// C1 — selling exactly 1 unit of PT. Price rounds up, so it never comes to 0.
test c1_sell_one_unit() {
  let p = price.price_of(1, 1_500, duration)
  let s = price.seller_fee_of(p, 10)
  let b = price.buyer_fee_of(p, 20)
  let inputs = [order_in(0, alice_vk, 1_500, 1)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [payout_out(alice_vk, p - s, fixture.min_ada), fixture.fee_out(s + b)]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    fee_value(s + b),
    tx_end(),
  )
}

/// C2 — the order holds a foreign token alongside the PT.
/// Loosening this would let junk be stuffed in and forced on the buyer.
test c2_order_holds_extra_token() fail {
  let base = order_in(0, alice_vk, 1_500, 1_000_000_000)
  let dirty =
    Input {
      ..base,
      output: Output {
        ..base.output,
        value: assets.add(base.output.value, fixture.junk_pid, "junk", 1),
      },
    }
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
      fixture.fee_out(s_fee_alice + b_fee_alice),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    [dirty],
    refs,
    outputs,
    fee_value(s_fee_alice + b_fee_alice),
    tx_end(),
  )
}

/// C3 — the order's datum does not parse as an AskDatum.
test c3_order_datum_unparseable() fail {
  let base = order_in(0, alice_vk, 1_500, 1_000_000_000)
  let broken =
    Input { ..base, output: Output { ..base.output, datum: InlineDatum(42) } }
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
      fixture.fee_out(s_fee_alice + b_fee_alice),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    [broken],
    refs,
    outputs,
    fee_value(s_fee_alice + b_fee_alice),
    tx_end(),
  )
}

// A shared frame for the scenarios that differ only in the remainder output.
fn buy_partial_with_cont(cont: Output) -> Bool {
  let inputs = [order_in(0, alice_vk, 1_800, 500_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      payout_out(alice_vk, price_bob - s_fee_bob, 0),
      cont,
      fixture.fee_out(s_fee_bob + b_fee_bob),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: 1 }])],
    inputs,
    refs,
    outputs,
    fee_value(s_fee_bob + b_fee_bob),
    tx_end(),
  )
}

// ------------------------------------------------------------ F1 and friends

/// F1 — two ask_limit deployment generations sharing ONE payout output.
///
/// The seller rests orders on both generations and the buyer builds a
/// transaction that pays exactly once; each validator sees only the input at
/// its own script hash, so both believe they were paid in full. The tag on the
/// output blocks it: two generations have different script hashes.
test f1_two_generations_share_payout() fail {
  let other_skh = #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"
  let inputs = [order_in(0, alice_vk, 1_500, 1_000_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  // The output carries the OTHER generation's tag
  let outputs =
    [
      Output {
        ..payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
        datum: InlineDatum(other_skh),
      },
      fixture.fee_out(s_fee_alice + b_fee_alice),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    fee_value(s_fee_alice + b_fee_alice),
    tx_end(),
  )
}

/// R1 — an empty fill list. Unblocked, anyone could build a withdraw-only
/// transaction to sweep the script's reward account.
test r1_empty_fills() fail {
  buy.verify(
    ask_skh,
    config(),
    [],
    [],
    [pool_ref(0, supply_maturity()), config_ref(1, config())],
    [],
    assets.zero,
    tx_end(),
  )
}

/// R1b — the list has a pool group, but that group holds no fills. It gets past
/// `pool_fills != []` and is then vacuously satisfied exactly as R1 is.
test r1b_empty_fill_group() fail {
  buy.verify(
    ask_skh,
    config(),
    [(0, [])],
    [],
    [pool_ref(0, supply_maturity()), config_ref(1, config())],
    [],
    assets.zero,
    tx_end(),
  )
}

/// R2 — the same order appearing twice in the fill list.
test r2_duplicate_order_in_fills() fail {
  let inputs = [order_in(0, alice_vk, 1_500, 1_000_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
      fixture.fee_out(( s_fee_alice + b_fee_alice ) * 2),
    ]
  buy.verify(
    ask_skh,
    config(),
    [
      (
        0,
        [
          Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 },
          Fill { order_in_idx: 0, owner_ou_idx: 1, cont_ou_idx: -1 },
        ],
      ),
    ],
    inputs,
    refs,
    outputs,
    fee_value(( s_fee_alice + b_fee_alice ) * 2),
    tx_end(),
  )
}

/// The ordinary-token origin branch: one unit short. a3 covers the ADA branch.
test a3b_token_origin_underpaid() fail {
  let inputs = [order_in(0, alice_vk, 1_500, 1_000_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      payout_out(alice_vk, price_alice - s_fee_alice - 1, fixture.min_ada),
      fixture.fee_out(s_fee_alice + b_fee_alice),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    fee_value(s_fee_alice + b_fee_alice),
    tx_end(),
  )
}

/// The ordinary-token origin branch: enough money paid, but the order's min ADA
/// swallowed.
test a3c_token_origin_swallows_min_ada() fail {
  let inputs = [order_in(0, alice_vk, 1_500, 1_000_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada - 1),
      fixture.fee_out(s_fee_alice + b_fee_alice),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    fee_value(s_fee_alice + b_fee_alice),
    tx_end(),
  )
}

/// An order carrying a non-positive yield. Create runs through no validator, so
/// a datum can hold anything; a negative yield large enough drives the
/// denominator to zero or below.
test a21_non_positive_yield() fail {
  let inputs = [order_in(0, alice_vk, 0, 1_000_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      payout_out(alice_vk, 1_000_000_000, fixture.min_ada),
      fixture.fee_out(1_000_000),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])],
    inputs,
    refs,
    outputs,
    fee_value(1_000_000),
    tx_end(),
  )
}

/// Buying exactly 0 PT: the remainder order keeps all the PT and still demands
/// the seller be paid.
test a22_zero_pt_sold() fail {
  let inputs = [order_in(0, bob_vk, 1_800, 500_000_000)]
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let outputs =
    [
      payout_out(bob_vk, 0, 0),
      cont_out(bob_vk, 1_800, 500_000_000),
      fixture.fee_out(0),
    ]
  buy.verify(
    ask_skh,
    config(),
    [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: 1 }])],
    inputs,
    refs,
    outputs,
    fee_value(0),
    tx_end(),
  )
}
