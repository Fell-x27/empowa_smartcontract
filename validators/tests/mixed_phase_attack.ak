use aiken/interval.{entirely_after}
use aiken/primitive/bytearray.{concat}
use cardano/assets.{from_asset, from_asset_list}
use cardano/transaction.{Input, NoDatum, Output, Transaction, placeholder}
use empowa_swap.{Bootstrap, Exchange, Recall}
use env.{
  burn_nft_name, burn_nft_pid, contract_address, contract_policy_id,
  contract_treasury_base_quantity, contract_treasury_marker_name,
  n2a_change_rate, owner_address, payout_asset_name, payout_asset_pid,
  start_change_time, unlock_unclaimed_assets_time, user_address,
  utxo_contract_ref, utxo_def_ref,
}

// Tests covering the mixed redeemer cases

test mixed_phase_attack_change_n_bootstrap() fail {
  // Let's try to bootstrap the contract with its own UTXO
  //
  //spend - exchange with 0 payouts
  //mint - bootstrap
  let contract_input =
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
        datum: NoDatum,
        reference_script: None,
      },
    )
  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [Pair(payout_asset_name, contract_treasury_base_quantity)],
          ), Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let mint_treasury_marker =
    from_asset(contract_policy_id, contract_treasury_marker_name, 1)
  let tx =
    Transaction {
      ..placeholder,
      inputs: [contract_input],
      outputs: [contract_output],
      mint: mint_treasury_marker,
      validity_range: entirely_after(start_change_time),
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
      redeemer: Exchange,
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
      redeemer: Bootstrap,
      contract_policy_id: contract_policy_id,
      tx: tx,
    ),
  }
}

test mixed_phase_attack_change_n_recall() fail {
  // What if the user performs a valid exchange after the recall timelock and tries to damage a treasury UTXO?
  //
  //spend - 100% valid exchange
  //mint - harmfull recall
  let user_input =
    Input(
      utxo_def_ref,
      Output {
        address: user_address,
        value: from_asset_list(
          [Pair(burn_nft_pid, [Pair(concat(burn_nft_name, "01"), 1)])],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let contract_input =
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
        datum: NoDatum,
        reference_script: None,
      },
    )

  let nft_burning =
    from_asset_list(
      [
        Pair(burn_nft_pid, [Pair(concat(burn_nft_name, "01"), -1)]),
        Pair(contract_policy_id, [Pair(contract_treasury_marker_name, -1)]),
      ],
    )

  //^marker is burned, so the treasury is disabled
  let user_output =
    Output {
      address: user_address,
      value: from_asset(payout_asset_pid, payout_asset_name, n2a_change_rate),
      //^ 1 NFT from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [
              Pair(
                payout_asset_name,
                contract_treasury_base_quantity - n2a_change_rate,
              ),
            ],
          ),
        ],
      ),
      // ^ 1 NFT were burned; the treasury balance was reduced accordingly.
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [contract_input, user_input],
      outputs: [contract_output, user_output],
      mint: nft_burning,
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
      redeemer: Exchange,
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
