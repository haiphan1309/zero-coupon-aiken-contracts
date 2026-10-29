//// Tests at validator level: the spend branch deferring to withdraw, withdraw
//// reading config, the fee output, and the validity range.
////
//// None of this can be checked by calling `sell.verify` directly — the TIME
//// BOUND least of all, since `sell.verify` takes `tx_start` as a parameter.

use aiken/interval
use bid_limit/bid_types.{
  BidLimitAction, BidLimitConfig, Fill, Sell, SellMulti, Update,
}
use bid_limit/fixture.{
  alice_vk, bid_amount, bid_skh, cfg_pid, cfg_tn, config, config_ref,
  fee_value_ada, maker_fee_full, min_ada, out_ref, pool_ref_ada, pt_full,
  reserve, supply_maturity, taker_fee_full, yield,
}
use cardano/address.{Script}
use cardano/transaction.{Transaction}
use daken/fixture/output_builder as ob
use daken/fixture/tx_builder as tb
use daken/time
use sc/sc_bid_limit

const fee_full = taker_fee_full + maker_fee_full

fn cfg_param() -> BidLimitConfig {
  BidLimitConfig { config_nft: (cfg_pid, cfg_tn) }
}

fn fills() -> List<(Int, List<Fill>)> {
  [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])]
}

fn action() -> BidLimitAction {
  BidLimitAction {
    indexers: SellMulti(fills()),
    order_in_idx: 0,
    config_ref_idx: 1,
    fee_ou_idx: 1,
  }
}

fn spend_action(order_in_idx: Int) -> BidLimitAction {
  BidLimitAction {
    indexers: Sell,
    order_in_idx,
    config_ref_idx: 0,
    fee_ou_idx: 0,
  }
}

fn base_tx() -> Transaction {
  fixture.mk_tx(
    [fixture.bid_in_ada(0, alice_vk, yield, bid_amount)],
    [pool_ref_ada(0, supply_maturity()), config_ref(1, config())],
    [
      fixture.payout_out_ada(alice_vk, pt_full, reserve),
      fixture.fee_out_ada(fee_full + min_ada),
    ],
    [],
  )
}

/// D1 — the full path through the withdraw branch.
///
/// ⚠️ This test is what pins the TIME BOUND. `pt_full` is the largest PT amount
/// `bid_amount` reaches WHEN anchored to `tx_start`: `cash_out` comes to exactly
/// 1_000_000_000. Switch `sc_bid_limit.withdraw` to the upper bound and
/// `duration` shortens by 300_000 ms, `cash_out` becomes 1_000_330_361, and
/// `expect cash_out <= bid_amount` fails at once.
test d1_withdraw_end_to_end() {
  sc_bid_limit.withdraw(cfg_param(), action(), Script(bid_skh), base_tx())
}

/// D2 — the spend branch proves its own order is in the list, then defers.
test d2_spend_delegates_to_withdraw() {
  let tx = base_tx() |> tb.add_zero_withdrawal_script(bid_skh, action())
  sc_bid_limit.spend(spend_action(0), out_ref(0), tx)
}

/// D3 — the fill list does not include the order being spent.
test d3_order_not_in_fills() fail {
  let other =
    BidLimitAction {
      ..action(),
      indexers: SellMulti(
        [(0, [Fill { order_in_idx: 1, owner_ou_idx: 0, cont_ou_idx: -1 }])],
      ),
    }
  let tx = base_tx() |> tb.add_zero_withdrawal_script(bid_skh, other)
  sc_bid_limit.spend(spend_action(0), out_ref(0), tx)
}

/// D4 — the withdraw redeemer is not SellMulti.
test d4_withdraw_redeemer_not_sell_multi() fail {
  let tx =
    base_tx()
      |> tb.add_zero_withdrawal_script(
          bid_skh,
          BidLimitAction { ..action(), indexers: Update(-1) },
        )
  sc_bid_limit.spend(spend_action(0), out_ref(0), tx)
}

/// D5 — no withdraw redeemer at all.
test d5_missing_withdraw_redeemer() fail {
  sc_bid_limit.spend(spend_action(0), out_ref(0), base_tx())
}

/// D6 — the spend branch for Update needs no withdraw.
test d6_spend_update_needs_no_withdraw() {
  let upd = BidLimitAction { ..action(), indexers: Update(-1) }
  let tx = Transaction { ..base_tx(), extra_signatories: [alice_vk] }
  sc_bid_limit.spend(upd, out_ref(0), tx)
}

/// D7 — the fee output is missing the `bid_skh` tag. The tag is checked by
/// withdraw, not by sell.
test d7_fee_output_without_tag() fail {
  let tx =
    Transaction {
      ..base_tx(),
      outputs: [
        fixture.payout_out_ada(alice_vk, pt_full, reserve),
        ob.new(fixture.wallet_addr(fixture.fee_vk))
          |> ob.add_lovelace(fee_full + min_ada),
      ],
    }
  sc_bid_limit.withdraw(cfg_param(), action(), Script(bid_skh), tx)
}

/// D8 — the fee output goes to an address other than `fee_addr`.
test d8_fee_output_wrong_address() fail {
  let tx =
    Transaction {
      ..base_tx(),
      outputs: [
        fixture.payout_out_ada(alice_vk, pt_full, reserve),
        ob.new(fixture.wallet_addr(fixture.bob_vk))
          |> ob.add_lovelace(fee_full + min_ada)
          |> ob.add_inline_datum(bid_skh),
      ],
    }
  sc_bid_limit.withdraw(cfg_param(), action(), Script(bid_skh), tx)
}

/// D9 — a validity range wider than `env.ttl`.
test d9_validity_range_too_wide() fail {
  let cfg = time.get_slot_config_network_preview()
  let wide =
    interval.between(
      time.slot_to_begin_posix_time(fixture.from_slot, cfg),
      time.slot_to_begin_posix_time(fixture.from_slot + 1_000, cfg),
    )
  let tx = Transaction { ..base_tx(), validity_range: wide }
  sc_bid_limit.withdraw(cfg_param(), action(), Script(bid_skh), tx)
}

/// D10 — with no lower bound there is nothing to anchor the price to.
test d10_no_lower_bound() fail {
  let cfg = time.get_slot_config_network_preview()
  let open_ended =
    interval.before(time.slot_to_begin_posix_time(fixture.to_slot, cfg))
  let tx = Transaction { ..base_tx(), validity_range: open_ended }
  sc_bid_limit.withdraw(cfg_param(), action(), Script(bid_skh), tx)
}

/// D11 — the config UTxO does not carry the right config NFT.
test d11_wrong_config_nft() fail {
  let bad = BidLimitConfig { config_nft: (cfg_pid, #"ffff") }
  sc_bid_limit.withdraw(bad, action(), Script(bid_skh), base_tx())
}

/// D12 — SellMulti is not usable on the spend branch.
test d12_sell_multi_on_spend() fail {
  sc_bid_limit.spend(action(), out_ref(0), base_tx())
}

/// D13 — `order_in_idx` points at an input other than the one being spent.
test d13_order_in_idx_mismatch() fail {
  let tx = base_tx() |> tb.add_zero_withdrawal_script(bid_skh, action())
  sc_bid_limit.spend(spend_action(0), out_ref(9), tx)
}
