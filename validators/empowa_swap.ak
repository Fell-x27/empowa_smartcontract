use aiken/collection/list.{all, any, foldl, length}
use cardano/address.{PaymentCredential}
use cardano/assets.{AssetName, PolicyId, quantity_of}
use cardano/transaction.{
  Input, Output, OutputReference, Transaction, find_script_outputs,
}
use config.{contract_treasury_asset_name}

pub type Action {
  Bootstrap
  Exchange
  Recall
}

validator empowa_swap(
  dist_asset_pid: PolicyId,
  dist_asset_name: AssetName,
  burn_nft_pid: PolicyId,
  burn_nft_name: AssetName,
  n2a_change_rate: Int,
  start_change_time: Int,
  unlock_unclaimed_assets_time: Int,
  unlock_unclaimed_assets_pcred: PaymentCredential,
) {
  spend(_d, redeemer: Action, _u, tx: Transaction) {
    // Exchange (sending EMP):
    // - Inputs:
    //   - ensure that the amount of EMP in the contract-owned tx_inputs covers the total of the burned tokens;
    //   - collect the list of addresses holding `nft_pid` NFTs with names starting with `nft_name`.
    // - Outputs:
    //   - ensure that the EMP difference between the contract's tx_outputs and tx_inputs equals the amount that must be paid to the user;
    //   - if multiple treasuries were used as tx_inputs (because one was not enough), only one or none should remain in the transaction tx_outputs;
    //   - ensure that there is at most one contract output with `contract_policy_id.contract_treasury_asset_name` (exactly 1 item);
    //   - ensure that all user tx_outputs match the user tx_inputs (NFT holders) by address and expected payout amount;
    //   - Ensure that no excess base ADA was withdrawn from the contract address, if any is present.
    // - Minting:
    //   - Check if any NFTs `nft_pid.nft_name...` were burned and that the payouts correspond to them;
    //   - Burning `contract_policy_id.contract_treasury_asset_name` is required if the treasury is empty.

    // Treasury destruction (recalling EMP and unlocking base ADA):
    //  Minting:
    //   - `contract_policy_id.contract_treasury_asset_name` < 0;
    // - Delegated to the mint() subvalidator.
    todo
  }

  mint(redeemer: Action, contract_policy_id: PolicyId, tx: Transaction) {
    let Transaction {
      inputs: tx_inputs,
      outputs: tx_outputs,
      mint: tx_mint,
      ..
    } = tx

    when redeemer is {
      Bootstrap -> {
        // Treasury formation (sending assets, minting the marker token):
        // - Redeemer: Bootstrap.
        // - Inputs:
        //   - ensure that `contract_policy_id.contract_treasury_asset_name` is not present in any input (it may only be minted);

        let no_markers_in_inputs =
          !any(
            tx_inputs,
            fn(Input { output: Output { value, .. }, .. }) {
              quantity_of(
                value,
                contract_policy_id,
                contract_treasury_asset_name,
              ) > 0
            },
          )

        // - Outputs:
        //   - verify that N EMP are sent to the contract address along with the `contract_policy_id.contract_treasury_asset_name` asset;
        // - AmountLock:
        //   - it's not allowed to create a treasury with less than 10,000 EMP;
        //   - it's not allowed to create a treasury with `contract_policy_id.contract_treasury_asset_name` != 1 .
        let script_outputs = find_script_outputs(tx_outputs, contract_policy_id)
        let script_outputs_are_fine =
          script_outputs
            |> all(
                fn(Output { value: script_output_value, .. }) {
                  and {
                    (quantity_of(
                      script_output_value,
                      contract_policy_id,
                      contract_treasury_asset_name,
                    ) == 1)?,
                    (quantity_of(
                      script_output_value,
                      dist_asset_pid,
                      dist_asset_name,
                    ) >= 10_000)?,
                  }
                },
              )

        // - Minting:
        //   - ensure that exactly 1 `contract_policy_id.contract_treasury_asset_name` per script_output was minted;
        let script_outputs_quantity = length(script_outputs)
        let minted_markers_quantity =
          quantity_of(tx_mint, contract_policy_id, contract_treasury_asset_name)
        let minted_markers_match_script_outputs =
          script_outputs_quantity == minted_markers_quantity

        and {
          no_markers_in_inputs?,
          script_outputs_are_fine?,
          minted_markers_match_script_outputs?,
        }
      }
      Recall ->
        // Treasury destruction (recalling EMP, unlocking base ADA, trashing empty treasury):
        // - Redeemer: Recall.
        // - Minting:
        //   - burning is allowed only after `unlock_unclaimed_assets_time`,
        //     or if the treasury UTXO contains no `dist_asset_pid.dist_asset_name` tokens;
        // - Outputs:
        //   - ensure that the only output goes to the address associated with `assets_owner_pcred`;
        //   - ensure that there are no tx_outputs containing `contract_policy_id.contract_treasury_asset_name`.
        todo @"Recall"

      Exchange ->
        // Exchange (sending EMP): 
        // - Ensure that the burned `contract_policy_id.contract_treasury_asset_name` comes from the single UTXO sent to the contract address.
        todo @"Exchange"
    }
  }

  else(_) {
    fail
  }
}
