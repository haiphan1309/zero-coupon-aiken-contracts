use ask_limit/ask_types.{AskDatum, AskLimitAction, AskLimitConfig}
use cardano/address.{Credential}
use cardano/script_context.{ScriptContext}
use cardano/transaction.{OutputReference, Transaction}
use sc/sc_ask_limit
use sc/sc_fallback

validator exec(cfg: AskLimitConfig) {
  // Creating an order runs no validator at all: it is a plain payment to the
  // script address carrying an inline datum. Everything that makes an order
  // well formed is enforced off-chain and by the indexer's filter.
  spend(
    _dt: Option<AskDatum>,
    rdmr: AskLimitAction,
    out_ref: OutputReference,
    tx: Transaction,
  ) {
    sc_ask_limit.spend(rdmr, out_ref, tx)
  }

  withdraw(rdmr: AskLimitAction, cre: Credential, tx: Transaction) {
    sc_ask_limit.withdraw(cfg, rdmr, cre, tx)
  }

  else(script_context: ScriptContext) {
    sc_fallback.fallback(script_context)
  }
}
