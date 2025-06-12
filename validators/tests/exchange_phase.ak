use aiken/primitive/bytearray.{concat}
use cardano/address.{Address, VerificationKey}
use cardano/assets.{add, from_asset, from_asset_list, from_lovelace}
use cardano/transaction.{Input, NoDatum, Output, Transaction, placeholder}
use empowa_swap.{Bootstrap, Exchange}
use env.{
  assets_owner_pcred, burn_nft_name, burn_nft_pid, contract_address,
  contract_pcred, contract_policy_id, contract_treasury_marker_name,
  dist_asset_name, dist_asset_pid, n2a_change_rate, start_change_time,
  unlock_unclaimed_assets_time, user_address, user_pcred, utxo_def_ref,
}

fn get_user_addr(pfx) {
  Address(VerificationKey(concat(pfx, "Some user")), None)
}

test succeed_exchange_treasury_part_consume() {
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "01"), 1),
                Pair(concat(burn_nft_name, "02"), 1),
                Pair(concat(burn_nft_name, "03"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("1"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "04"), 1),
                Pair(concat(burn_nft_name, "05"), 1),
                Pair(concat(burn_nft_name, "06"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let script_input =
    Input(
      utxo_def_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(dist_asset_pid, [Pair(dist_asset_name, 10_000)]),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The user requests to burn some of their NFTs (not necessarily all of them).
  let nft_burning =
    from_asset_list(
      [
        Pair(
          burn_nft_pid,
          [
            Pair(concat(burn_nft_name, "01"), 1),
            Pair(concat(burn_nft_name, "03"), 1),
            Pair(concat(burn_nft_name, "06"), 1),
          ],
        ),
      ],
    )

  // The user expects to receive EMP according to the established exchange rate.
  let user_output_0 =
    Output {
      address: get_user_addr("0"),
      value: from_asset(dist_asset_pid, dist_asset_name, n2a_change_rate * 2),
      //^ 2 NFTs from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_1 =
    Output {
      address: get_user_addr("0"),
      value: from_asset(dist_asset_pid, dist_asset_name, n2a_change_rate),
      //^ 1 NFT from the second addr was burned
      datum: NoDatum,
      reference_script: None,
    }

  // The contract expects the change (leftover EMP) to be returned to a treasury UTXO, marked with a treasury marker.
  let script_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            dist_asset_pid,
            [Pair(dist_asset_name, 10_000 - n2a_change_rate * 3)],
          ),
          // ^ 3 NFTs were burned; the treasury balance was reduced accordingly.
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1, script_input],
      outputs: [user_output_0, user_output_1, script_output],
      mint: nft_burning,
    }
  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  and {
    empowa_swap.empowa_swap.mint(
      dist_asset_pid: dist_asset_pid,
      dist_asset_name: dist_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      unlock_unclaimed_assets_pcred: assets_owner_pcred,
      redeemer: Exchange,
      contract_policy_id: contract_policy_id,
      tx: tx,
    ),
    empowa_swap.empowa_swap.spend(
      //datum
      None,
      //utxo ref
      Void,
      dist_asset_pid: dist_asset_pid,
      dist_asset_name: dist_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      unlock_unclaimed_assets_pcred: assets_owner_pcred,
      redeemer: Exchange,
      tx: tx,
    ),
  }
}
