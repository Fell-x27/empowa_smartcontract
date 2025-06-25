use aiken/collection/list
use aiken/interval.{after, before, entirely_after, entirely_before}
use aiken/primitive/bytearray.{concat}
use cardano/address.{Address, VerificationKey}
use cardano/assets.{
  ada_asset_name, ada_policy_id, add, from_asset, from_asset_list, from_lovelace,
}
use cardano/transaction.{Input, NoDatum, Output, Transaction, placeholder}
use config.{contract_treasury_lovelace}
use empowa_swap.{Bootstrap, Exchange}
use env.{
  burn_nft_name, burn_nft_pid, contract_address, contract_pcred,
  contract_policy_id, contract_treasury_base_quantity,
  contract_treasury_marker_name, n2a_change_rate, owner_address,
  payout_asset_name, payout_asset_pid, start_change_time,
  unlock_unclaimed_assets_time, user_address, user_pcred, utxo_contract_ref,
  utxo_def_ref,
}
// Test covering the mixed redeemer cases

// test mixed_phase_attack_change_n_bootstrap() {
//   // Let's try to bootstrap the contract with its own UTXO
//   //
//   //spend - exchange with 0 payouts
//   //mint - bootstrap
//   let contract_input =
//     Input(
//       utxo_contract_ref,
//       Output {
//         address: contract_address,
//         value: from_asset_list(
//           [
//             Pair(
//               payout_asset_pid,
//               [Pair(payout_asset_name, contract_treasury_base_quantity)],
//             ),
//             Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
//           ],
//         ),
//         datum: NoDatum,
//         reference_script: None,
//       },
//     )
//   let contract_output =
//     Input(
//       utxo_contract_ref,
//       Output {
//         address: contract_address,
//         value: from_asset_list(
//           [
//             Pair(
//               payout_asset_pid,
//               [Pair(payout_asset_name, contract_treasury_base_quantity)],
//             ),
//             Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 2)]),
//           ],
//         ),
//         datum: NoDatum,
//         reference_script: None,
//       },
//     )

//   let mint_treasury_marker =
//     from_asset(contract_policy_id, contract_treasury_marker_name, 1)

//   True
// }
