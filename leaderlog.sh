#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2086,SC2154,SC2034,SC2012,SC2140,SC2028


# usage() {
#   cat <<-EOF >&2
    
#     Usage: $(basename "$0") [operation <sub arg>]
#     Script to run Leaderlog
    
#     force     Manually force leaderlog calculation and overwrite even if already done, exits after leaderlog is calculated
    
#     EOF
#   exit 1
# }

if [[ $# -eq 1 ]]; then
  subarg=$1
fi




PARENT="$(dirname $0)"
. "${PARENT}"/env


  TMP_DIR="${TMP_DIR}/cncli"
  if ! mkdir -p "${TMP_DIR}" 2>/dev/null; then echo "ERROR: Failed to create directory for temporary files: ${TMP_DIR}"; exit 1; fi
  
  [[ ! -f "${CNCLI}" ]] && echo -e "\nERROR: failed to locate cncli executable, please install with 'prereqs.sh'\n" && exit 1
  CNCLI_VERSION="v$(cncli -V | cut -d' ' -f2)"
  if ! versionCheck "2.1.0" "${CNCLI_VERSION}"; then echo "ERROR: cncli ${CNCLI_VERSION} installed, minimum required version is 2.1.0, please upgrade to latest version!"; exit 1; fi
  
  [[ -z "${CNCLI_DIR}" ]] && CNCLI_DIR="${CNODE_HOME}/guild-db/cncli"
  if ! mkdir -p "${CNCLI_DIR}" 2>/dev/null; then echo "ERROR: Failed to create CNCLI DB directory: ${CNCLI_DIR}"; exit 1; fi
  CNCLI_DB="${CNCLI_DIR}/cncli.db"
  [[ -z "${LEDGER_API}" ]] && LEDGER_API=false
  [[ -z "${SLEEP_RATE}" ]] && SLEEP_RATE=60
  [[ -z "${CONFIRM_SLOT_CNT}" ]] && CONFIRM_SLOT_CNT=600
  [[ -z "${CONFIRM_BLOCK_CNT}" ]] && CONFIRM_BLOCK_CNT=15
  [[ -z "${PT_HOST}" ]] && PT_HOST="127.0.0.1"
  [[ -z "${PT_PORT}" ]] && PT_PORT="${CNODE_PORT}"
  [[ -z "${PT_SENDSLOTS_START}" ]] && PT_SENDSLOTS_START=30
  PT_SENDSLOTS_START=$((PT_SENDSLOTS_START*60))
  [[ -z "${PT_SENDSLOTS_STOP}" ]] && PT_SENDSLOTS_STOP=60
  PT_SENDSLOTS_STOP=$((PT_SENDSLOTS_STOP*60))
  if [[ -d "${POOL_DIR}" ]]; then
    [[ -z "${POOL_ID}" && -f "${POOL_DIR}/${POOL_ID_FILENAME}" ]] && POOL_ID=$(cat "${POOL_DIR}/${POOL_ID_FILENAME}")
    [[ -z "${POOL_VRF_SKEY}" ]] && POOL_VRF_SKEY="${POOL_DIR}/${POOL_VRF_SK_FILENAME}"
    [[ -z "${POOL_VRF_VKEY}" ]] && POOL_VRF_VKEY="${POOL_DIR}/${POOL_VRF_VK_FILENAME}"
  fi

getLedgerData() { # getNodeMetrics expected to have been already run
  if ! stake_snapshot=$(${CCLI} query stake-snapshot --stake-pool-id ${POOL_ID} ${NETWORK_IDENTIFIER} 2>&1); then
    echo "ERROR: stake-snapshot query failed: ${stake_snapshot}"
    return 1
  fi
  #pool_stake_go=$(jq -r .poolStakeGo <<< ${stake_snapshot})
  #active_stake_go=$(jq -r .activeStakeGo <<< ${stake_snapshot})
  pool_stake_mark=$(jq -r .poolStakeMark <<< ${stake_snapshot})
  active_stake_mark=$(jq -r .activeStakeMark <<< ${stake_snapshot})
  pool_stake_set=$(jq -r .poolStakeSet <<< ${stake_snapshot})
  active_stake_set=$(jq -r .activeStakeSet <<< ${stake_snapshot})
  return 0
}






getNodeMetrics
curr_epoch=${epochnum}
next_epoch=$((curr_epoch+1))


#    RUNNING THE CNCLI COMMAND
echo "Running leaderlogs for epoch[${next_epoch}]"

echo -e "CNCLI : ${CNCLI}"
echo -e "Pool id : ${POOL_ID}"
echo -e "\n\n"

if [[ $(sqlite3 "${BLOCKLOG_DB}" "SELECT COUNT(*) FROM epochdata WHERE epoch=${next_epoch};" 2>/dev/null) -eq 1 && ${subarg} != "force" ]]; then
  
  echo "Leaderlogs already calculated for epoch ${next_epoch}, skipping!"

  #    PRINT VAL from json without cncli  can run only after ran 1 time with cncli
  cncli_leaderlog="leaderlog${next_epoch}.json"
  echo "Showing leaderlogs for epoch[${next_epoch}] from ${cncli_leaderlog}"


  echo -e "\n\n"
  

  epoch_nonce=$(jq -r '.epochNonce' "${cncli_leaderlog}")
  echo -e "Epoch nonce        : ${epoch_nonce}"
  pool_id=$(jq -r '.poolId' "${cncli_leaderlog}")
  echo -e "Pool-id            : ${pool_id}"
  sigma=$(jq -r '.sigma' "${cncli_leaderlog}")
  echo -e "Sigma              : ${sigma}"
  d=$(jq -r '.d' "${cncli_leaderlog}")
  echo -e "d                  : ${d}"
  epoch_slots_ideal=$(jq -r '.epochSlotsIdeal //0' "${cncli_leaderlog}")
  echo -e "Epoch slots ideal  : ${epoch_slots_ideal}"
  max_performance=$(jq -r '.maxPerformance //0' "${cncli_leaderlog}")
  echo -e "Max Preformance    : ${max_performance}"
  active_stake=$(jq -r '.activeStake //0' "${cncli_leaderlog}")
  echo -e "Active Stake       : ${active_stake}"
  total_active_stake=$(jq -r '.totalActiveStake //0' "${cncli_leaderlog}")
  echo -e "Total Active Stake : ${total_active_stake}"

  echo -e "\n\n"
  # END PRINT


else



  echo "Running leaderlogs for epoch ${next_epoch} and adding leader slots not already in DB"
  stake_param_current=""
  if [[ ${LEDGER_API} = false || ${NWMAGIC} -ne 764824073 ]]; then 
    if ! getLedgerData; then exit 1; else stake_param_current="--active-stake ${active_stake_set} --pool-stake ${pool_stake_set}"; fi
  fi
  cncli_leaderlog=$(${CNCLI} leaderlog --db "${CNCLI_DB}" --byron-genesis "${BYRON_GENESIS_JSON}" --shelley-genesis "${GENESIS_JSON}" --ledger-set current ${stake_param_current} --pool-id "${POOL_ID}" --pool-vrf-skey "${POOL_VRF_SKEY}" --tz UTC)
  if [[ $(jq -r .status <<< "${cncli_leaderlog}") != ok ]]; then
    error_msg=$(jq -r .errorMessage <<< "${cncli_leaderlog}")
    if [[ "${error_msg}" = "Query returned no rows" ]]; then
      echo "No leader slots found for epoch ${next_epoch} :("
    else
      echo "ERROR: failure in leaderlog while running:"
      echo "${CNCLI} leaderlog --db ${CNCLI_DB} --byron-genesis ${BYRON_GENESIS_JSON} --shelley-genesis ${GENESIS_JSON} --ledger-set current ${stake_param_current} --pool-id ${POOL_ID} --pool-vrf-skey ${POOL_VRF_SKEY} --tz UTC"
      echo "Error message: ${error_msg}"
      exit 1
    fi
  else



      ##    Write Json file
      echo "${cncli_leaderlog}" > "leaderlog${next_epoch}.json"

  #    END CNCLI COMMAND

      #    PRINT VAL after cncli
      echo -e "Pool Stake Mark    : ${pool_stake_mark}"
      echo -e "Active Stake Mark  : ${active_stake_mark}"
      echo -e "Pool Stake Set     : ${pool_stake_set}"
      echo -e "Active Stake Mark  : ${active_stake_set}"  
      echo -e ""
      epoch_nonce=$(jq -r '.epochNonce' <<< "${cncli_leaderlog}")
      echo -e "Epoch nonce        : ${epoch_nonce}"
      pool_id=$(jq -r '.poolId' <<< "${cncli_leaderlog}")
      echo -e "Pool-id            : ${pool_id}"
      sigma=$(jq -r '.sigma' <<< "${cncli_leaderlog}")
      echo -e "Sigma              : ${sigma}"
      d=$(jq -r '.d' <<< "${cncli_leaderlog}")
      echo -e "d                  : ${d}"
      epoch_slots_ideal=$(jq -r '.epochSlotsIdeal //0' <<< "${cncli_leaderlog}")
      echo -e "Epoch slots ideal  : ${epoch_slots_ideal}"
      max_performance=$(jq -r '.maxPerformance //0' <<< "${cncli_leaderlog}")
      echo -e "Max Preformance    : ${max_performance}"
      active_stake=$(jq -r '.activeStake //0' <<< "${cncli_leaderlog}")
      echo -e "Active Stake       : ${active_stake}"
      total_active_stake=$(jq -r '.totalActiveStake //0' <<< "${cncli_leaderlog}")
      echo -e "Total Active Stake : ${total_active_stake}"
      #    END OF PRINT VAL after cncli
        


  ###       Writing into DB
  ###

        sqlite3 ${BLOCKLOG_DB} <<-EOF
          UPDATE OR IGNORE epochdata SET epoch_nonce = '${epoch_nonce}', sigma = '${sigma}', d = ${d}, epoch_slots_ideal = ${epoch_slots_ideal}, max_performance = ${max_performance}, active_stake = '${active_stake}', total_active_stake = '${total_active_stake}'
          WHERE epoch = ${next_epoch} AND pool_id = '${pool_id}';
          INSERT OR IGNORE INTO epochdata (epoch, epoch_nonce, pool_id, sigma, d, epoch_slots_ideal, max_performance, active_stake, total_active_stake)
          VALUES (${next_epoch}, '${epoch_nonce}', '${pool_id}', '${sigma}', ${d}, ${epoch_slots_ideal}, ${max_performance}, '${active_stake}', '${total_active_stake}');
EOF
      block_cnt=0
      while read -r assigned_slot; do
        block_slot=$(jq -r '.slot' <<< "${assigned_slot}")
        block_at=$(jq -r '.at' <<< "${assigned_slot}")
        block_slot_in_epoch=$(jq -r '.slotInEpoch' <<< "${assigned_slot}")
        sqlite3 "${BLOCKLOG_DB}" "INSERT OR IGNORE INTO blocklog (slot,at,slot_in_epoch,epoch,status) values (${block_slot},'${block_at}',${block_slot_in_epoch},${next_epoch},'leader');"
        echo "LEADER: slot[${block_slot}] slotInEpoch[${block_slot_in_epoch}] at[${block_at}]"
        ((block_cnt++))
      done  < <(jq -c '.assignedSlots[]' <<< "${cncli_leaderlog}" 2>/dev/null)
  echo "Leaderlog calculation for epoch[${next_epoch}] completed and saved to blocklog DB"
  echo "Leaderslots: ${block_cnt} - Ideal slots for epoch based on active stake: ${epoch_slots_ideal} - Luck factor ${max_performance}%"
  fi



#### Reading from db
epoch_enter=${next_epoch}
echo -e "${epoch_enter}"
sigma=$(sqlite3 "${BLOCKLOG_DB}" "SELECT sigma FROM epochdata WHERE epoch=${epoch_enter};" 2>/dev/null)
epoch_slot_ideal=$(sqlite3 "${BLOCKLOG_DB}" "SELECT sigma FROM epochdata WHERE epoch=${epoch_enter};" 2>/dev/null)
#"$(sqlite3 "${BLOCKLOG_DB}" "SELECT epoch_slots_ideal, max_performance FROM epochdata WHERE epoch=${epoch_enter};" 2>/dev/null)"
 # invalid_cnt=$(sqlite3 "${BLOCKLOG_DB}" "SELECT COUNT(*) FROM blocklog WHERE epoch=${epoch_enter} AND status='invalid';" 2>/dev/null)
echo -e "sigma : ${sigma}"


echo "END"
fi