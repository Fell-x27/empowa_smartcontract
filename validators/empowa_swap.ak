use cardano/address.{PaymentCredential}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}

pub type Action {
  Bootstrap
  Exchange
  Recall
}

validator empowa_swap(
  asset_pid: PolicyId,
  asset_name: AssetName,
  nft_pid: PolicyId,
  nft_name: AssetName,
  n2a_change_rate: Int,
  start_change_time: Int,
  unlock_unclaimed_assets_time: Int,
  unlock_unclaimed_assets_pcred: PaymentCredential,
) {
  spend(_d, redeemer: Action, _u, tx: Transaction) {
    // Exchange (sending EMP):
    // - Inputs:
    //   - ensure that the amount of EMP in the contract-owned inputs covers the total of the burned tokens;
    //   - collect the list of addresses holding `nft_pid` NFTs with names starting with `nft_name`.
    // - Outputs:
    //   - ensure that the EMP difference between the contract's outputs and inputs equals the amount that must be paid to the user;
    //   - if multiple treasuries were used as inputs (because one was not enough), only one or none should remain in the transaction outputs;
    //   - ensure that there is at most one contract output with `contract_policy_id.contract_treasury_asset_name` (exactly 1 item);
    //   - ensure that all user outputs match the user inputs (NFT holders) by address and expected payout amount;
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

  mint(redeemer: Action, contract_pid: PolicyId, tx: Transaction) {
    let Transaction { inputs, outputs, mint, .. } = tx

    when redeemer is {
      Bootstrap ->
        // Treasury formation (sending assets, minting the marker token):
        // - Redeemer: Bootstrap.
        // - Inputs:
        //   - ensure that `contract_policy_id.contract_treasury_asset_name` is not present in any input (it may only be minted);
        // - Outputs:
        //   - verify that N EMP are sent to the contract address along with the `contract_policy_id.contract_treasury_asset_name` asset;
        // - Minting:
        //   - ensure that exactly 1 `contract_treasury_asset_name` was minted;
        // - AmountLock:
        //   - it's not allowed to create a treasury with less than 10,000 EMP.
        todo @"Bootstrap"

      Recall ->
        // Treasury destruction (recalling EMP, unlocking base ADA, trashing empty treasury):
        // - Redeemer: Recall.
        // - Minting:
        //   - burning is allowed only after `unlock_unclaimed_assets_time`,
        //     or if the treasury UTXO contains no `dist_asset_pid.dist_asset_name` tokens;
        // - Outputs:
        //   - ensure that the only output goes to the address associated with `assets_owner_pcred`;
        //   - ensure that there are no outputs containing `contract_policy_id.contract_treasury_asset_name`.
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
