use cardano/script_context.{ScriptContext}
use cardano/transaction.{Transaction}
use daken/util as daken_util
use env

pub fn fallback(
  ScriptContext {
    transaction: Transaction { inputs, reference_inputs, extra_signatories, .. },
    ..
  }: ScriptContext,
) {
  // Required nft_license in inputs or reference_inputs of transaction
  // Required signatory from the owner of nft_license
  daken_util.has_valid_nft_license(
    inputs,
    reference_inputs,
    extra_signatories,
    env.license_nft_pid,
    env.license_nft_tn,
  )?
}
