use aiken/interval.{before, entirely_after}
use cardano/assets.{from_asset, from_asset_list, from_lovelace}
use cardano/transaction.{Input, NoDatum, Output, Transaction, placeholder}
use config.{contract_treasury_lovelace}
use empowa_swap.{Recall}
use env.{
  burn_nft_name, burn_nft_pid, contract_address, contract_policy_id,
  contract_treasury_base_quantity, contract_treasury_marker_name,
  n2a_change_rate, owner_address, payout_asset_name, payout_asset_pid,
  start_change_time, unlock_unclaimed_assets_time, user_address,
  utxo_contract_ref,
}

// After a certain time range, we should be able to recall any remaining UTXOs from the contract's address.

test succeed_recall() {
  //contract inputs only
  let contract_input_example =
    Input(
      utxo_contract_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(
              payout_asset_pid,
              [Pair(payout_asset_name, contract_treasury_base_quantity)],
            ),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        //^the value doesn't matter acrually, but it's better to burn the marker

        datum: NoDatum,
        reference_script: None,
      },
    )

  let owner_output =
    Output {
      address: owner_address,
      value: from_lovelace(contract_treasury_lovelace),
      //^the value doesn't matter acrually
      datum: NoDatum,
      reference_script: None,
    }

  let markers_burning =
    from_asset(contract_policy_id, contract_treasury_marker_name, -3)

  let tx =
    Transaction {
      ..placeholder,
      inputs: [
        contract_input_example, contract_input_example, contract_input_example,
      ],
      outputs: [owner_output],
      mint: markers_burning,
      validity_range: entirely_after(unlock_unclaimed_assets_time),
    }

  and {
    empowa_swap.empowa_swap.spend(
      //datum
      None,
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Recall,
      contract_utxo: utxo_contract_ref,
      tx: tx,
    ),
    empowa_swap.empowa_swap.mint(
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Recall,
      contract_policy_id: contract_policy_id,
      tx: tx,
    ),
  }
}

test succeed_recall_non_treasury_utxo() {
  //contract inputs only
  let contract_input_example =
    Input(
      utxo_contract_ref,
      Output {
        address: contract_address,
        value: from_lovelace(10_000_000),
        //^the value doesn't matter acrually, but it's better to burn the marker

        datum: NoDatum,
        reference_script: None,
      },
    )

  let owner_output =
    Output {
      address: owner_address,
      value: from_lovelace(10_000_000),
      //^the value doesn't matter acrually
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [contract_input_example],
      outputs: [owner_output],
      validity_range: entirely_after(unlock_unclaimed_assets_time),
    }

  empowa_swap.empowa_swap.spend(
    //datum
    None,
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Recall,
    contract_utxo: utxo_contract_ref,
    tx: tx,
  )
}

test failed_recall_to_many_outputs() fail {
  //contract inputs only
  let contract_input_example =
    Input(
      utxo_contract_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(
              payout_asset_pid,
              [Pair(payout_asset_name, contract_treasury_base_quantity)],
            ),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        //^the value doesn't matter acrually, but it's better to burn the marker

        datum: NoDatum,
        reference_script: None,
      },
    )

  let owner_output =
    Output {
      address: owner_address,
      value: from_lovelace(contract_treasury_lovelace / 2),
      //^the value doesn't matter acrually
      datum: NoDatum,
      reference_script: None,
    }

  let user_output =
    Output {
      address: user_address,
      value: from_lovelace(contract_treasury_lovelace / 2),
      //^the value doesn't matter acrually
      datum: NoDatum,
      reference_script: None,
    }

  let markers_burning =
    from_asset(contract_policy_id, contract_treasury_marker_name, -3)

  let tx =
    Transaction {
      ..placeholder,
      inputs: [
        contract_input_example, contract_input_example, contract_input_example,
      ],
      outputs: [owner_output, user_output],
      mint: markers_burning,
      validity_range: entirely_after(unlock_unclaimed_assets_time),
    }

  and {
    empowa_swap.empowa_swap.spend(
      //datum
      None,
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Recall,
      contract_utxo: utxo_contract_ref,
      tx: tx,
    ),
    empowa_swap.empowa_swap.mint(
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Recall,
      contract_policy_id: contract_policy_id,
      tx: tx,
    ),
  }
}

test failed_recall_to_user_address() fail {
  //contract inputs only
  let contract_input_example =
    Input(
      utxo_contract_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(
              payout_asset_pid,
              [Pair(payout_asset_name, contract_treasury_base_quantity)],
            ),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        //^the value doesn't matter acrually, but it's better to burn the marker

        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_output =
    Output {
      address: user_address,
      value: from_lovelace(contract_treasury_lovelace / 2),
      //^the value doesn't matter acrually
      datum: NoDatum,
      reference_script: None,
    }

  let markers_burning =
    from_asset(contract_policy_id, contract_treasury_marker_name, -3)

  let tx =
    Transaction {
      ..placeholder,
      inputs: [
        contract_input_example, contract_input_example, contract_input_example,
      ],
      outputs: [user_output],
      mint: markers_burning,
      validity_range: entirely_after(unlock_unclaimed_assets_time),
    }

  and {
    empowa_swap.empowa_swap.spend(
      //datum
      None,
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Recall,
      contract_utxo: utxo_contract_ref,
      tx: tx,
    ),
    empowa_swap.empowa_swap.mint(
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Recall,
      contract_policy_id: contract_policy_id,
      tx: tx,
    ),
  }
}

test failed_recall_before_timelock() fail {
  //contract inputs only
  let contract_input_example =
    Input(
      utxo_contract_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(
              payout_asset_pid,
              [Pair(payout_asset_name, contract_treasury_base_quantity)],
            ),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        //^the value doesn't matter acrually, but it's better to burn the marker

        datum: NoDatum,
        reference_script: None,
      },
    )

  let owner_output =
    Output {
      address: owner_address,
      value: from_lovelace(contract_treasury_lovelace),
      //^the value doesn't matter acrually
      datum: NoDatum,
      reference_script: None,
    }

  let markers_burning =
    from_asset(contract_policy_id, contract_treasury_marker_name, -3)

  let tx =
    Transaction {
      ..placeholder,
      inputs: [
        contract_input_example, contract_input_example, contract_input_example,
      ],
      outputs: [owner_output],
      mint: markers_burning,
      validity_range: before(unlock_unclaimed_assets_time),
    }

  and {
    empowa_swap.empowa_swap.spend(
      //datum
      None,
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Recall,
      contract_utxo: utxo_contract_ref,
      tx: tx,
    ),
    empowa_swap.empowa_swap.mint(
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Recall,
      contract_policy_id: contract_policy_id,
      tx: tx,
    ),
  }
}
