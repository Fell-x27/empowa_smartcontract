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
    //   - collect the list of addresses holding NFTs with names starting with `nft_name`.
    // - Outputs:
    //   - ensure that the EMP difference between the contract's outputs and inputs equals the amount that must be paid to the user;
    //   - if multiple treasuries were used as inputs (because one was not enough), only one or none should remain in the transaction outputs;
    //   - ensure that there is at most one contract output with `contract_policy_id.contract_treasury_asset_name` (exactly 1 item);
    //   - ensure that all user outputs match the user inputs (NFT holders) by address and expected payout amount.

    // Treasury destruction (recalling EMP and unlocking base ADA):
    // - Delegated to the mint() subvalidator.
    todo
  }

  mint(redeemer: Action, contract_pid: PolicyId, tx: Transaction) {
    // Treasury formation (sending assets, minting the marker token):
    // - Inputs:
    //   - ensure that `contract_treasury_asset_name` is not present in any input (it may only be minted);
    // - Outputs:
    //   - verify that N EMP are sent to the contract address along with the `contract_policy_id.contract_treasury_asset_name` asset;
    // - Minting:
    //   - ensure that exactly 1 `contract_treasury_asset_name` was minted;
    // - AmountLock:
    //   - it's not allowed to create a treasury with less than 10,000 EMP.

    // Treasury destruction (recalling EMP, unlocking base ADA, trashing empty treasury):
    // - Minting:
    //   - burning is allowed only after `unlock_unclaimed_assets_time`,
    //     or if the treasury UTXO contains no `dist_asset_pid.dist_asset_name` tokens;
    // - Outputs:
    //   - ensure that the only output goes to the address associated with `assets_owner_pcred`.
    todo
  }

  else(_) {
    fail
  }
}
