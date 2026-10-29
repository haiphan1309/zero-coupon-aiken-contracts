//// Tests at validator level: the spend branch deferring to withdraw, and the
//// withdraw side reading config and the validity range.
////
//// None of this can be checked by calling `buy.verify` directly: the relation
//// between the spend redeemer and the withdraw redeemer, reading the config
//// UTxO, and handling the validity range through daken.

use aiken/interval
use ask_limit/ask_types.{
  AskLimitAction, AskLimitConfig, Buy, BuyMulti, Fill, Update,
}
use ask_limit/fixture.{
  alice_vk, ask_skh, cfg_pid, cfg_tn, config, config_ref, fee_value, order_in,
  out_ref, payout_out, pool_ref, supply_maturity, valid_range,
}
use cardano/address.{Script}
use cardano/assets
use cardano/transaction.{InlineDatum, NoDatum, Output, Transaction}
use daken/fixture/tx_builder as tb
use daken/time
use sc/sc_ask_limit

const price_alice = 964_332_893

const s_fee_alice = 964_332

const b_fee_alice = 1_928_666

fn cfg_param() -> AskLimitConfig {
  AskLimitConfig { config_nft: (cfg_pid, cfg_tn) }
}

fn fills() -> List<(Int, List<Fill>)> {
  [(0, [Fill { order_in_idx: 0, owner_ou_idx: 0, cont_ou_idx: -1 }])]
}

/// The withdraw branch's redeemer: it carries the fill list.
fn action() -> AskLimitAction {
  AskLimitAction {
    indexers: BuyMulti(fills()),
    order_in_idx: 0,
    config_ref_idx: 1,
    fee_ou_idx: 1,
  }
}

/// The spend branch's redeemer: it carries NO list, only a pointer to its own
/// input.
fn spend_action(order_in_idx: Int) -> AskLimitAction {
  AskLimitAction {
    indexers: Buy,
    order_in_idx,
    config_ref_idx: 0,
    fee_ou_idx: 0,
  }
}

fn base_tx() -> Transaction {
  fixture.mk_tx(
    [order_in(0, alice_vk, 1_500, 1_000_000_000)],
    [pool_ref(0, supply_maturity()), config_ref(1, config())],
    [
      payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
      fixture.fee_out(s_fee_alice + b_fee_alice),
    ],
    [],
  )
}

/// The full path through the withdraw branch: read config from a reference
/// input, check the validity range through daken, take tx_end, compute price.
test b_withdraw_end_to_end() {
  sc_ask_limit.withdraw(cfg_param(), action(), Script(ask_skh), base_tx())
}

/// The spend branch proves its own order is in the fill list, then defers to a
/// withdraw carrying exactly the same `indexers`.
test b_spend_delegates_to_withdraw() {
  let tx = base_tx() |> tb.add_zero_withdrawal_script(ask_skh, action())
  sc_ask_limit.spend(spend_action(0), out_ref(0), tx)
}

/// A5 — the fill list does not include the order being spent.
test a5_order_not_in_fills() fail {
  let other =
    AskLimitAction {
      ..action(),
      indexers: BuyMulti(
        [(0, [Fill { order_in_idx: 1, owner_ou_idx: 0, cont_ou_idx: -1 }])],
      ),
    }
  let tx = base_tx() |> tb.add_zero_withdrawal_script(ask_skh, other)
  sc_ask_limit.spend(spend_action(0), out_ref(0), tx)
}

/// A6 — the withdraw redeemer is not BuyMulti.
///
/// The spend branch reads the fill list straight out of the withdraw redeemer
/// rather than carrying its own and comparing, so "spend and withdraw disagree
/// about the list" no longer exists as a state. What still has to be blocked is
/// a withdraw of another shape.
test a6_withdraw_redeemer_not_buy_multi() fail {
  let tx =
    base_tx()
      |> tb.add_zero_withdrawal_script(
          ask_skh,
          AskLimitAction { ..action(), indexers: Update(-1) },
        )
  sc_ask_limit.spend(spend_action(0), out_ref(0), tx)
}

/// A6b — no withdraw redeemer at all.
test a6b_missing_withdraw_redeemer() fail {
  sc_ask_limit.spend(spend_action(0), out_ref(0), base_tx())
}

/// The spend branch for Update needs no withdraw.
test b_spend_update_needs_no_withdraw() {
  let upd = AskLimitAction { ..action(), indexers: Update(-1) }
  let tx = Transaction { ..base_tx(), extra_signatories: [alice_vk] }
  sc_ask_limit.spend(upd, out_ref(0), tx)
}

/// C5 — a validity range wider than `env.ttl`.
test c5_validity_range_too_wide() fail {
  let cfg = time.get_slot_config_network_preview()
  let wide =
    interval.between(
      time.slot_to_begin_posix_time(fixture.to_slot - 1_000, cfg),
      time.slot_to_begin_posix_time(fixture.to_slot, cfg),
    )
  let tx = Transaction { ..base_tx(), validity_range: wide }
  sc_ask_limit.withdraw(cfg_param(), action(), Script(ask_skh), tx)
}

/// C6 — with no upper bound there is nothing to anchor the price to.
test c6_no_upper_bound() fail {
  let cfg = time.get_slot_config_network_preview()
  let open_ended =
    interval.after(time.slot_to_begin_posix_time(fixture.from_slot, cfg))
  let tx = Transaction { ..base_tx(), validity_range: open_ended }
  sc_ask_limit.withdraw(cfg_param(), action(), Script(ask_skh), tx)
}

/// C7 — config_ref_idx points at a UTxO that does not carry the config NFT.
test c7_config_ref_without_nft() fail {
  let bad = AskLimitAction { ..action(), config_ref_idx: 0 }
  sc_ask_limit.withdraw(cfg_param(), bad, Script(ask_skh), base_tx())
}

/// F1b — the fee output carries no script-hash tag.
///
/// Without the tag, two deployment generations share one fee output and the
/// protocol collects only half. It has to be tested at the withdraw level,
/// because `buy.verify` receives a `fee_val` that is already checked.
test f1b_fee_output_untagged() fail {
  let tx =
    Transaction {
      ..base_tx(),
      outputs: [
        payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
        Output { ..fixture.fee_out(s_fee_alice + b_fee_alice), datum: NoDatum },
      ],
    }
  sc_ask_limit.withdraw(cfg_param(), action(), Script(ask_skh), tx)
}

/// F1c — the fee output carries another generation's tag.
test f1c_fee_output_wrong_tag() fail {
  let other_skh = #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"
  let tx =
    Transaction {
      ..base_tx(),
      outputs: [
        payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
        Output {
          ..fixture.fee_out(s_fee_alice + b_fee_alice),
          datum: InlineDatum(other_skh),
        },
      ],
    }
  sc_ask_limit.withdraw(cfg_param(), action(), Script(ask_skh), tx)
}

/// F4 — mixing a cancel into the same transaction as a fill, which is allowed.
/// Every ask input runs its own spend branch, so "every order is checked" holds
/// even though the cancelled input has no matching fill.
test f4_cancel_alongside_buy() {
  let cancel_order = order_in(5, fixture.bob_vk, 1_800, 400_000_000)
  let tx =
    Transaction {
      ..base_tx(),
      inputs: [order_in(0, alice_vk, 1_500, 1_000_000_000), cancel_order],
      extra_signatories: [fixture.bob_vk],
    }
  sc_ask_limit.withdraw(cfg_param(), action(), Script(ask_skh), tx)
}

/// C7b — the fee output goes to the wrong address.
test c7b_fee_output_wrong_address() fail {
  let tx =
    Transaction {
      ..base_tx(),
      outputs: [
        payout_out(alice_vk, price_alice - s_fee_alice, fixture.min_ada),
        payout_out(fixture.bob_vk, s_fee_alice + b_fee_alice, fixture.min_ada),
      ],
    }
  sc_ask_limit.withdraw(cfg_param(), action(), Script(ask_skh), tx)
}

/// The fixture's validity range sits wholly before the price anchor, and that
/// anchor is the upper bound — exactly what `buy.verify` receives.
test fixture_range_ends_at_tx_end() {
  and {
    fee_value(1) != assets.zero,
    interval.is_entirely_before(valid_range(), fixture.tx_end() + 1),
  }
}
