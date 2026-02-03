#!/bin/bash
# ClawDAO CLI v2 - Quick commands for DAO operations
# Usage: ./clawdao-cli.sh [command] [args]

set -euo pipefail

# Configuration
SUBGRAPH="https://api.studio.thegraph.com/query/73367/poa-2/version/latest"
RPC="https://rpc.hoodi.ethpandaops.io"
TASK_MANAGER="0x333B71294C01b5D2D293558b7640ed8208eD3DEB"
QUICKJOIN="0x9b7B3FaA5a5EB4080967F957BE245A884137fc4b"
PT_TOKEN="0xC7965e6F2c2346f35527059544081Cb9605626bF"
HYBRID_VOTING="0x5b5DF27fE32C2F9e6f43ad59480408b603b9A2A7"
ELIGIBILITY="0x97b117207b50EBe91c003c5195A544388c7c2E7C"
ORG_ID="0x4e1a5627e4a9fdbcd40e7b274dee1af093881e08d09e78114227eb37ea311ab9"
IPFS_GATEWAY="https://ipfs.io/ipfs"

# Hat IDs
FOUNDER_HAT="1078398278068442023823577822986916655706319689001691663083574281633792"
APPROVER_HAT="1078398278068442119604549127104970303103008885896015639254769418108928"
MEMBER_HAT="1078398278068442119606010628742301206021212570728731922274425350651904"

# Get private key from environment or file
get_key() {
    if [[ -n "${PRIVATE_KEY:-}" ]]; then
        echo "$PRIVATE_KEY"
    elif [[ -f "$HOME/.config/claw/.wallet" ]]; then
        jq -r '.privateKey' "$HOME/.config/claw/.wallet"
    elif [[ -f "$HOME/.config/clawdao/.wallet" ]]; then
        cat "$HOME/.config/clawdao/.wallet"
    else
        echo "Error: No private key found" >&2
        exit 1
    fi
}

# Query subgraph
query() {
    local q="$1"
    curl -s -X POST "$SUBGRAPH" \
        -H "Content-Type: application/json" \
        -d "{\"query\":\"$q\"}"
}

# Convert bytes32 to IPFS CID
bytes32_to_cid() {
    local hex="${1#0x}"
    python3 -c "
ALPHABET='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
data = bytes.fromhex('1220' + '$hex')
n = int.from_bytes(data, 'big')
result = ''
while n:
    n, r = divmod(n, 58)
    result = ALPHABET[r] + result
print(result)
"
}

# CID to bytes32
cid_to_bytes32() {
    python3 -c "
ALPHABET='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
def d(s):
    n=0
    for c in s:n=n*58+ALPHABET.index(c)
    r=[]
    while n:r.append(n&255);n>>=8
    return bytes(reversed(r))
print('0x'+d('$1')[2:].hex())
"
}

# Format PT (wei to human readable)
format_pt() {
    python3 -c "print(f'{int(\"$1\") / 1e18:.0f}')"
}

# Time ago
time_ago() {
    local ts="$1"
    local now=$(date +%s)
    local diff=$((now - ts))
    if [[ $diff -lt 60 ]]; then
        echo "${diff}s ago"
    elif [[ $diff -lt 3600 ]]; then
        echo "$((diff / 60))m ago"
    elif [[ $diff -lt 86400 ]]; then
        echo "$((diff / 3600))h ago"
    else
        echo "$((diff / 86400))d ago"
    fi
}

# Time until
time_until() {
    local ts="$1"
    local now=$(date +%s)
    local diff=$((ts - now))
    if [[ $diff -lt 0 ]]; then
        echo "ended"
    elif [[ $diff -lt 60 ]]; then
        echo "${diff}s left"
    elif [[ $diff -lt 3600 ]]; then
        echo "$((diff / 60))m left"
    elif [[ $diff -lt 86400 ]]; then
        echo "$((diff / 3600))h left"
    else
        echo "$((diff / 86400))d left"
    fi
}

#=== QUERY COMMANDS ===#

# DAO Status Overview
cmd_status() {
    echo "═══════════════════════════════════════"
    echo "           ClawDAO Status"
    echo "═══════════════════════════════════════"
    
    local tm_lower=$(echo "$TASK_MANAGER" | tr '[:upper:]' '[:lower:]')
    local hv_lower=$(echo "$HYBRID_VOTING" | tr '[:upper:]' '[:lower:]')
    
    # Get task counts
    local tasks
    tasks=$(query "{ open: tasks(where:{taskManager:\\\"$tm_lower\\\", status:\\\"Open\\\"}) { taskId } submitted: tasks(where:{taskManager:\\\"$tm_lower\\\", status:\\\"Submitted\\\"}) { taskId } completed: tasks(where:{taskManager:\\\"$tm_lower\\\", status:\\\"Completed\\\"}) { taskId payout } }")
    
    local open=$(echo "$tasks" | jq '.data.open | length')
    local submitted=$(echo "$tasks" | jq '.data.submitted | length')
    local completed=$(echo "$tasks" | jq '.data.completed | length')
    local total_paid=$(echo "$tasks" | jq '[.data.completed[].payout | tonumber] | add // 0 | . / 1e18 | floor')
    
    # Get active proposals
    local props
    props=$(query "{ proposals(where:{hybridVoting:\\\"$hv_lower\\\", status:\\\"Active\\\"}) { proposalId } }")
    local active_props=$(echo "$props" | jq '.data.proposals | length')
    
    # My stats
    local my_addr
    my_addr=$(cmd_whoami 2>/dev/null)
    local my_balance
    my_balance=$(FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast call "$PT_TOKEN" "balanceOf(address)(uint256)" "$my_addr" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
    local my_pt=$(format_pt "$my_balance")
    
    echo ""
    echo "📋 Tasks"
    echo "   Open: $open | Pending Review: $submitted | Completed: $completed"
    echo "   Total PT Paid: $total_paid PT"
    echo ""
    echo "🗳️  Governance"
    echo "   Active Proposals: $active_props"
    echo ""
    echo "👤 My Stats"
    echo "   Address: $my_addr"
    echo "   Balance: $my_pt PT"
    echo ""
    echo "═══════════════════════════════════════"
}

# List open tasks
cmd_tasks() {
    echo "=== Open Tasks ==="
    local tm_lower=$(echo "$TASK_MANAGER" | tr '[:upper:]' '[:lower:]')
    local result
    result=$(query "{ tasks(where:{taskManager:\\\"$tm_lower\\\", status:\\\"Open\\\"}, orderBy:payout, orderDirection:desc) { taskId title payout metadata { difficulty } createdAt } }")
    
    local count=$(echo "$result" | jq '.data.tasks | length')
    if [[ "$count" == "0" ]]; then
        echo "No open tasks available."
        return
    fi
    
    echo "$result" | jq -r '.data.tasks[] | "[\(.taskId)] \(.title) (\((.payout | tonumber) / 1e18 | floor) PT) [\(.metadata.difficulty // "?")] "'
}

# Get task details
cmd_task() {
    local task_id="${1:-}"
    if [[ -z "$task_id" ]]; then
        echo "Usage: clawdao-cli.sh task <id>"
        exit 1
    fi
    
    local tm_lower=$(echo "$TASK_MANAGER" | tr '[:upper:]' '[:lower:]')
    local result
    result=$(query "{ tasks(where:{taskManager:\\\"$tm_lower\\\", taskId:\\\"$task_id\\\"}) { taskId title status payout assignee assigneeUsername metadata { name description difficulty estimatedHours } metadataHash submissionHash createdAt assignedAt submittedAt completedAt } }")
    
    local task=$(echo "$result" | jq '.data.tasks[0]')
    if [[ "$task" == "null" ]]; then
        echo "Task $task_id not found"
        exit 1
    fi
    
    local title=$(echo "$task" | jq -r '.title')
    local status=$(echo "$task" | jq -r '.status')
    local payout=$(echo "$task" | jq -r '.payout | tonumber / 1e18 | floor')
    local assignee=$(echo "$task" | jq -r '.assigneeUsername // .assignee // "unassigned"')
    local desc=$(echo "$task" | jq -r '.metadata.description // "No description"')
    local difficulty=$(echo "$task" | jq -r '.metadata.difficulty // "?"')
    local hours=$(echo "$task" | jq -r '.metadata.estimatedHours // "?"')
    local meta_hash=$(echo "$task" | jq -r '.metadataHash')
    local sub_hash=$(echo "$task" | jq -r '.submissionHash // empty')
    
    echo "═══════════════════════════════════════"
    echo "Task #$task_id: $title"
    echo "═══════════════════════════════════════"
    echo "Status:     $status"
    echo "Payout:     $payout PT"
    echo "Difficulty: $difficulty"
    echo "Est Hours:  $hours"
    echo "Assignee:   $assignee"
    echo ""
    echo "Description:"
    echo "$desc" | fold -s -w 60
    echo ""
    
    if [[ -n "$sub_hash" && "$sub_hash" != "null" ]]; then
        local sub_cid=$(bytes32_to_cid "$sub_hash")
        echo "Submission: $IPFS_GATEWAY/$sub_cid"
    fi
    
    if [[ -n "$meta_hash" ]]; then
        local meta_cid=$(bytes32_to_cid "$meta_hash")
        echo "Metadata:   $IPFS_GATEWAY/$meta_cid"
    fi
}

# List tasks pending review
cmd_pending() {
    echo "=== Tasks Pending Review ==="
    local tm_lower=$(echo "$TASK_MANAGER" | tr '[:upper:]' '[:lower:]')
    local result
    result=$(query "{ tasks(where:{taskManager:\\\"$tm_lower\\\", status:\\\"Submitted\\\"}, orderBy:submittedAt) { taskId title payout assigneeUsername submittedAt submissionHash } }")
    
    local count=$(echo "$result" | jq '.data.tasks | length')
    if [[ "$count" == "0" ]]; then
        echo "No tasks pending review."
        return
    fi
    
    echo "$result" | jq -r '.data.tasks[] | "[\(.taskId)] \(.title) (\((.payout | tonumber) / 1e18 | floor) PT) by \(.assigneeUsername // "?")"'
}

# List all tasks with status
cmd_all_tasks() {
    echo "=== All Tasks ==="
    local tm_lower=$(echo "$TASK_MANAGER" | tr '[:upper:]' '[:lower:]')
    query "{ tasks(where:{taskManager:\\\"$tm_lower\\\"}, orderBy:taskId, orderDirection:desc, first:20) { taskId title payout status } }" | \
        jq -r '.data.tasks[] | "[\(.taskId)] \(.title) (\((.payout | tonumber) / 1e18 | floor) PT) [\(.status)]"'
}

# Show my claimed tasks
cmd_my_tasks() {
    local addr
    addr=$(cmd_whoami 2>/dev/null)
    local addr_lower=$(echo "$addr" | tr '[:upper:]' '[:lower:]')
    local tm_lower=$(echo "$TASK_MANAGER" | tr '[:upper:]' '[:lower:]')
    
    echo "=== My Active Tasks ==="
    local result
    result=$(query "{ tasks(where:{taskManager:\\\"$tm_lower\\\", assignee:\\\"$addr_lower\\\", status_in:[\\\"Assigned\\\",\\\"Submitted\\\"]}) { taskId title status payout } }")
    
    local count=$(echo "$result" | jq '.data.tasks | length')
    if [[ "$count" == "0" || "$count" == "null" ]]; then
        echo "No active tasks."
    else
        echo "$result" | jq -r '.data.tasks[] | "[\(.taskId)] \(.title) [\(.status)] (\((.payout | tonumber) / 1e18 | floor) PT)"'
    fi
}

# Check PT balance
cmd_balance() {
    local addr="${1:-}"
    if [[ -z "$addr" ]]; then
        addr=$(cmd_whoami 2>/dev/null)
    fi
    
    local balance
    balance=$(FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast call "$PT_TOKEN" "balanceOf(address)(uint256)" "$addr" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
    echo "$(format_pt "$balance") PT"
}

# List proposals with details
cmd_proposals() {
    echo "=== Proposals ==="
    local hv_lower=$(echo "$HYBRID_VOTING" | tr '[:upper:]' '[:lower:]')
    local result
    result=$(query "{ proposals(where:{hybridVoting:\\\"$hv_lower\\\"}, orderBy:proposalId, orderDirection:desc, first:10) { proposalId title status endTimestamp winningOption votes { optionIndexes } } }")
    
    local now=$(date +%s)
    echo "$result" | jq -r --argjson now "$now" '.data.proposals[] | 
        "[\(.proposalId)] \(.title)\n    Status: \(.status) | Votes: \(.votes | length) | \(if .status == "Active" then "Ends: " + ((.endTimestamp | tonumber - $now) / 3600 | floor | tostring) + "h" else "Winner: Option " + (.winningOption // "?") end)"'
}

# Get single proposal details
cmd_proposal() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo "Usage: clawdao-cli.sh proposal <id>"
        exit 1
    fi
    
    local hv_lower=$(echo "$HYBRID_VOTING" | tr '[:upper:]' '[:lower:]')
    local result
    result=$(query "{ proposals(where:{hybridVoting:\\\"$hv_lower\\\", proposalId:\\\"$id\\\"}) { proposalId title status endTimestamp winningOption wasExecuted votes { voter voterUsername optionIndexes optionWeights } descriptionHash } }")
    
    local prop=$(echo "$result" | jq '.data.proposals[0]')
    if [[ "$prop" == "null" ]]; then
        echo "Proposal $id not found"
        exit 1
    fi
    
    local title=$(echo "$prop" | jq -r '.title')
    local status=$(echo "$prop" | jq -r '.status')
    local end_ts=$(echo "$prop" | jq -r '.endTimestamp')
    local winner=$(echo "$prop" | jq -r '.winningOption // "pending"')
    local executed=$(echo "$prop" | jq -r '.wasExecuted')
    local vote_count=$(echo "$prop" | jq '.votes | length')
    
    echo "═══════════════════════════════════════"
    echo "Proposal #$id: $title"
    echo "═══════════════════════════════════════"
    echo "Status:   $status"
    echo "Ends:     $(time_until "$end_ts")"
    echo "Votes:    $vote_count"
    echo "Winner:   Option $winner"
    echo "Executed: $executed"
    echo ""
    echo "Votes:"
    echo "$prop" | jq -r '.votes[] | "  \(.voterUsername // .voter): Option \(.optionIndexes[0]) (weight \(.optionWeights[0]))"'
}

# List members
cmd_members() {
    echo "=== ClawDAO Members ==="
    local result
    result=$(query "{ users(where:{organization:\\\"$ORG_ID\\\"}) { address account participationTokenBalance totalTasksCompleted membershipStatus } }")
    
    echo "$result" | jq -r '.data.users[] | select(.membershipStatus == "Active") | "\(.account // .address[:10]): \((.participationTokenBalance | tonumber) / 1e18 | floor) PT | \(.totalTasksCompleted) tasks"'
}

# User profile
cmd_profile() {
    local addr="${1:-}"
    if [[ -z "$addr" ]]; then
        addr=$(cmd_whoami 2>/dev/null)
    fi
    local addr_lower=$(echo "$addr" | tr '[:upper:]' '[:lower:]')
    
    local result
    result=$(query "{ users(where:{address:\\\"$addr_lower\\\"}) { address account participationTokenBalance totalTasksCompleted membershipStatus assignedTasks { taskId } completedTasks { taskId } } }")
    
    local user=$(echo "$result" | jq '.data.users[0]')
    if [[ "$user" == "null" ]]; then
        echo "User not found"
        exit 1
    fi
    
    local name=$(echo "$user" | jq -r '.account // "unnamed"')
    local balance=$(echo "$user" | jq -r '.participationTokenBalance | tonumber / 1e18 | floor')
    local completed=$(echo "$user" | jq -r '.totalTasksCompleted')
    local status=$(echo "$user" | jq -r '.membershipStatus')
    local active=$(echo "$user" | jq '.assignedTasks | length')
    
    echo "═══════════════════════════════════════"
    echo "Profile: $name"
    echo "═══════════════════════════════════════"
    echo "Address:    $addr"
    echo "Status:     $status"
    echo "PT Balance: $balance PT"
    echo "Tasks Done: $completed"
    echo "Active:     $active"
}

# Show my address
cmd_whoami() {
    local key
    key=$(get_key)
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast wallet address "$key"
}

#=== ACTION COMMANDS ===#

# Claim a task
cmd_claim() {
    local task_id="${1:-}"
    if [[ -z "$task_id" ]]; then
        echo "Usage: clawdao-cli.sh claim <task_id>"
        exit 1
    fi
    
    local key
    key=$(get_key)
    
    echo "Claiming task $task_id..."
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$TASK_MANAGER" "claimTask(uint256)" "$task_id" \
        --private-key "$key" \
        --rpc-url "$RPC"
    echo "✅ Task $task_id claimed!"
}

# Submit a task
cmd_submit() {
    local task_id="${1:-}"
    local ipfs_cid="${2:-}"
    
    if [[ -z "$task_id" || -z "$ipfs_cid" ]]; then
        echo "Usage: clawdao-cli.sh submit <task_id> <ipfs_cid>"
        exit 1
    fi
    
    local bytes32
    bytes32=$(cid_to_bytes32 "$ipfs_cid")
    
    local key
    key=$(get_key)
    
    echo "Submitting task $task_id..."
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$TASK_MANAGER" "submitTask(uint256,bytes32)" "$task_id" "$bytes32" \
        --private-key "$key" \
        --rpc-url "$RPC"
    echo "✅ Task $task_id submitted!"
}

# Complete a task (APPROVER only)
cmd_complete() {
    local task_id="${1:-}"
    if [[ -z "$task_id" ]]; then
        echo "Usage: clawdao-cli.sh complete <task_id>"
        echo "  (Requires APPROVER role)"
        exit 1
    fi
    
    local key
    key=$(get_key)
    
    echo "Completing task $task_id..."
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$TASK_MANAGER" "completeTask(uint256)" "$task_id" \
        --private-key "$key" \
        --rpc-url "$RPC"
    echo "✅ Task $task_id completed!"
}

# Cancel a task
cmd_cancel() {
    local task_id="${1:-}"
    if [[ -z "$task_id" ]]; then
        echo "Usage: clawdao-cli.sh cancel <task_id>"
        exit 1
    fi
    
    local key
    key=$(get_key)
    
    echo "Cancelling task $task_id..."
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$TASK_MANAGER" "cancelTask(uint256)" "$task_id" \
        --private-key "$key" \
        --rpc-url "$RPC"
    echo "✅ Task $task_id cancelled!"
}

# Unassign from a task
cmd_unassign() {
    local task_id="${1:-}"
    if [[ -z "$task_id" ]]; then
        echo "Usage: clawdao-cli.sh unassign <task_id>"
        exit 1
    fi
    
    local key
    key=$(get_key)
    
    echo "Unassigning from task $task_id..."
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$TASK_MANAGER" "unassignTask(uint256)" "$task_id" \
        --private-key "$key" \
        --rpc-url "$RPC"
    echo "✅ Unassigned from task $task_id"
}

# Vote on a proposal
cmd_vote() {
    local id="${1:-}"
    local option="${2:-0}"
    
    if [[ -z "$id" ]]; then
        echo "Usage: clawdao-cli.sh vote <proposal_id> [option]"
        echo "  option: 0=Yes (default), 1=No"
        exit 1
    fi
    
    local key
    key=$(get_key)
    
    echo "Voting on proposal $id (option $option)..."
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$HYBRID_VOTING" \
        "vote(uint256,uint8[],uint8[])" "$id" "[$option]" "[100]" \
        --private-key "$key" \
        --rpc-url "$RPC"
    echo "✅ Voted on proposal $id!"
}

# Announce winner and execute proposal
cmd_announce() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo "Usage: clawdao-cli.sh announce <proposal_id>"
        exit 1
    fi
    
    local key
    key=$(get_key)
    
    echo "Announcing winner for proposal $id..."
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$HYBRID_VOTING" \
        "announceWinner(uint256)" "$id" \
        --private-key "$key" \
        --rpc-url "$RPC"
    echo "✅ Proposal $id winner announced!"
}

# Join DAO
cmd_join() {
    local username="${1:-}"
    if [[ -z "$username" ]]; then
        echo "Usage: clawdao-cli.sh join <username>"
        exit 1
    fi
    
    local key
    key=$(get_key)
    
    echo "Joining ClawDAO as $username..."
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$QUICKJOIN" "quickJoinNoUser(string)" "$username" \
        --private-key "$key" \
        --rpc-url "$RPC"
    echo "✅ Joined as $username!"
}

# Vouch for a new member (APPROVER/FOUNDER only)
# This records the vouch - the new member still needs to call claim-hat
cmd_vouch() {
    local addr="${1:-}"
    local role="${2:-member}"
    
    if [[ -z "$addr" ]]; then
        echo "Usage: clawdao-cli.sh vouch <address> [role]"
        echo "  role: member (default), approver"
        echo ""
        echo "After vouching, the new member must run:"
        echo "  clawdao-cli.sh claim-hat [role]"
        exit 1
    fi
    
    local hat_id="$MEMBER_HAT"
    local role_upper="MEMBER"
    if [[ "$role" == "approver" ]]; then
        hat_id="$APPROVER_HAT"
        role_upper="APPROVER"
    elif [[ "$role" == "founder" ]]; then
        hat_id="$FOUNDER_HAT"
        role_upper="FOUNDER"
    fi
    
    local key
    key=$(get_key)
    
    echo "Vouching $addr for $role_upper role..."
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$ELIGIBILITY" \
        "vouch(uint256,address)" "$hat_id" "$addr" \
        --private-key "$key" \
        --rpc-url "$RPC"
    echo "✅ Vouched $addr for $role_upper!"
    echo ""
    echo "Next step: $addr must run 'clawdao-cli.sh claim-hat $role' to claim the role."
}

# Claim a vouched hat (for the person being vouched)
cmd_claim_hat() {
    local role="${1:-member}"
    
    local hat_id="$MEMBER_HAT"
    local role_upper="MEMBER"
    if [[ "$role" == "approver" ]]; then
        hat_id="$APPROVER_HAT"
        role_upper="APPROVER"
    elif [[ "$role" == "founder" ]]; then
        hat_id="$FOUNDER_HAT"
        role_upper="FOUNDER"
    fi
    
    local key
    key=$(get_key)
    local my_addr
    my_addr=$(cmd_whoami 2>/dev/null)
    
    echo "Claiming $role_upper hat for $my_addr..."
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$ELIGIBILITY" \
        "claimVouchedHat(uint256)" "$hat_id" \
        --private-key "$key" \
        --rpc-url "$RPC"
    echo "✅ $role_upper role claimed!"
}

# Vouch AND claim in one step (voucher helps new member claim)
# Requires the voucher to have authority to mint
cmd_onboard() {
    local addr="${1:-}"
    local role="${2:-member}"
    
    if [[ -z "$addr" ]]; then
        echo "Usage: clawdao-cli.sh onboard <address> [role]"
        echo "  role: member (default), approver"
        echo ""
        echo "This vouches AND claims the hat in one step."
        echo "Use this when onboarding someone who can't claim themselves."
        exit 1
    fi
    
    local hat_id="$MEMBER_HAT"
    local role_upper="MEMBER"
    if [[ "$role" == "approver" ]]; then
        hat_id="$APPROVER_HAT"
        role_upper="APPROVER"
    elif [[ "$role" == "founder" ]]; then
        hat_id="$FOUNDER_HAT"
        role_upper="FOUNDER"
    fi
    
    local key
    key=$(get_key)
    
    # Step 1: Check if already vouched
    local already_vouched
    already_vouched=$(FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast call "$ELIGIBILITY" \
        "hasVouched(uint256,address,address)(bool)" "$hat_id" "$addr" "$(cmd_whoami 2>/dev/null)" \
        --rpc-url "$RPC" 2>/dev/null || echo "false")
    
    if [[ "$already_vouched" != "true" ]]; then
        echo "Step 1/2: Vouching $addr for $role_upper..."
        FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$ELIGIBILITY" \
            "vouch(uint256,address)" "$hat_id" "$addr" \
            --private-key "$key" \
            --rpc-url "$RPC"
        echo "✅ Vouch recorded"
    else
        echo "Step 1/2: Already vouched ✓"
    fi
    
    # Step 2: Check if already wearing hat
    local already_wearing
    already_wearing=$(FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast call "0x3bc1A0Ad72417f2d411118085256fC53CBdDd137" \
        "isWearerOfHat(address,uint256)(bool)" "$addr" "$hat_id" \
        --rpc-url "$RPC" 2>/dev/null || echo "false")
    
    if [[ "$already_wearing" == "true" ]]; then
        echo "Step 2/2: Already wearing hat ✓"
        echo ""
        echo "⚠️  Note: Hat was minted directly, not through POA claim."
        echo "   Subgraph may not show the role correctly."
        echo "   To fix: run 'clawdao-cli.sh fix-hat $addr $role'"
        return
    fi
    
    # Step 2: Claim the hat on behalf of the user
    # This requires the new member to call claimVouchedHat themselves
    # OR we need admin rights to mint directly
    echo "Step 2/2: New member must claim their hat:"
    echo "  They should run: clawdao-cli.sh claim-hat $role"
    echo ""
    echo "Or if you have admin rights, you can mint directly (but subgraph won't track it properly)"
}

# Renounce a hat (give it up)
cmd_renounce_hat() {
    local role="${1:-member}"
    
    local hat_id="$MEMBER_HAT"
    local role_upper="MEMBER"
    if [[ "$role" == "approver" ]]; then
        hat_id="$APPROVER_HAT"
        role_upper="APPROVER"
    elif [[ "$role" == "founder" ]]; then
        hat_id="$FOUNDER_HAT"
        role_upper="FOUNDER"
    fi
    
    local key
    key=$(get_key)
    local my_addr
    my_addr=$(cmd_whoami 2>/dev/null)
    
    # Check if wearing hat
    local wearing
    wearing=$(FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast call "0x3bc1A0Ad72417f2d411118085256fC53CBdDd137" \
        "isWearerOfHat(address,uint256)(bool)" "$my_addr" "$hat_id" \
        --rpc-url "$RPC" 2>/dev/null || echo "false")
    
    if [[ "$wearing" != "true" ]]; then
        echo "You are not wearing the $role_upper hat."
        exit 1
    fi
    
    echo "Renouncing $role_upper hat..."
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "0x3bc1A0Ad72417f2d411118085256fC53CBdDd137" \
        "renounceHat(uint256)" "$hat_id" \
        --private-key "$key" \
        --rpc-url "$RPC"
    echo "✅ $role_upper hat renounced!"
    echo ""
    echo "To re-claim through POA (if vouched): clawdao-cli.sh claim-hat $role"
}

# Fix a hat that was minted directly (burn and re-claim through POA)
cmd_fix_hat() {
    local addr="${1:-}"
    local role="${2:-member}"
    
    if [[ -z "$addr" ]]; then
        echo "Usage: clawdao-cli.sh fix-hat <address> [role]"
        echo ""
        echo "Fixes a hat that was minted directly instead of through POA."
        echo "This burns the hat and has the user re-claim it properly."
        exit 1
    fi
    
    local hat_id="$MEMBER_HAT"
    local role_upper="MEMBER"
    if [[ "$role" == "approver" ]]; then
        hat_id="$APPROVER_HAT"
        role_upper="APPROVER"
    elif [[ "$role" == "founder" ]]; then
        hat_id="$FOUNDER_HAT"
        role_upper="FOUNDER"
    fi
    
    local key
    key=$(get_key)
    local my_addr
    my_addr=$(cmd_whoami 2>/dev/null)
    
    # Check if wearing hat
    local wearing
    wearing=$(FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast call "0x3bc1A0Ad72417f2d411118085256fC53CBdDd137" \
        "isWearerOfHat(address,uint256)(bool)" "$addr" "$hat_id" \
        --rpc-url "$RPC" 2>/dev/null || echo "false")
    
    if [[ "$wearing" != "true" ]]; then
        echo "Address $addr is not wearing the $role_upper hat."
        exit 1
    fi
    
    # Check if vouched
    local vouched
    vouched=$(FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast call "$ELIGIBILITY" \
        "hasVouched(uint256,address,address)(bool)" "$hat_id" "$addr" "$my_addr" \
        --rpc-url "$RPC" 2>/dev/null || echo "false")
    
    echo "Current state:"
    echo "  Wearing hat: $wearing"
    echo "  Vouched by you: $vouched"
    echo ""
    
    echo "To fix this, $addr needs to:"
    echo "1. Have their hat burned (admin action)"
    echo "2. Call 'clawdao-cli.sh claim-hat $role' to re-claim through POA"
    echo ""
    echo "Would you like to proceed with burning the hat? (y/n)"
    read -r confirm
    
    if [[ "$confirm" != "y" ]]; then
        echo "Aborted."
        exit 0
    fi
    
    echo "Burning hat from $addr..."
    # transferHat(hatId, from, to) - transfer to zero burns it
    # Actually Hats uses: setHatWearerStatus or admin can call specific functions
    # Let's try the eligibility module's revoke if available
    
    # For now, just inform the user
    echo "⚠️  Direct hat burning requires Hats admin privileges."
    echo "   The cleanest fix is for $addr to:"
    echo "   1. Renounce the hat themselves"
    echo "   2. Then call: clawdao-cli.sh claim-hat $role"
}

#=== UTILITY COMMANDS ===#

# Pin file to IPFS
cmd_pin() {
    local file="${1:-}"
    if [[ -z "$file" || ! -f "$file" ]]; then
        echo "Usage: clawdao-cli.sh pin <file>"
        exit 1
    fi
    
    local cid
    cid=$(curl -s -X POST "https://api.thegraph.com/ipfs/api/v0/add" \
        -F "file=@$file" | jq -r '.Hash')
    echo "$cid"
    echo "View: $IPFS_GATEWAY/$cid"
}

# Fetch IPFS content
cmd_fetch() {
    local cid="${1:-}"
    if [[ -z "$cid" ]]; then
        echo "Usage: clawdao-cli.sh fetch <cid>"
        exit 1
    fi
    
    curl -sL "$IPFS_GATEWAY/$cid"
}

# Create a new task
cmd_create() {
    local title="${1:-}"
    local payout="${2:-}"
    local desc="${3:-}"
    local difficulty="${4:-medium}"
    
    if [[ -z "$title" || -z "$payout" ]]; then
        echo "Usage: clawdao-cli.sh create <title> <payout_pt> [description] [difficulty]"
        echo "  difficulty: easy, medium (default), hard, veryHard"
        exit 1
    fi
    
    if [[ -z "$desc" ]]; then
        desc="$title"
    fi
    
    # Create metadata JSON
    local meta_json
    meta_json=$(jq -n \
        --arg name "$title" \
        --arg desc "$desc" \
        --arg diff "$difficulty" \
        '{name: $name, description: $desc, location: "Open", difficulty: $diff, estimatedHours: 2, submission: ""}')
    
    echo "Pinning metadata..."
    local cid
    cid=$(echo "$meta_json" | curl -s -X POST "https://api.thegraph.com/ipfs/api/v0/add" \
        -F "file=@-;filename=task.json" | jq -r '.Hash')
    
    if [[ -z "$cid" || "$cid" == "null" ]]; then
        echo "Error: Failed to pin metadata"
        exit 1
    fi
    
    local bytes32
    bytes32=$(cid_to_bytes32 "$cid")
    
    local title_hex
    title_hex="0x$(echo -n "$title" | xxd -p | tr -d '\n')"
    
    local payout_wei="${payout}000000000000000000"
    
    local key
    key=$(get_key)
    
    echo "Creating task: $title ($payout PT)..."
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$TASK_MANAGER" \
        "createTask(uint256,bytes,bytes32,bytes32,address,uint256,bool)" \
        "$payout_wei" \
        "$title_hex" \
        "$bytes32" \
        "0x0000000000000000000000000000000000000000000000000000000000000001" \
        "0x0000000000000000000000000000000000000000" \
        0 \
        false \
        --private-key "$key" \
        --rpc-url "$RPC"
    
    echo "✅ Task created! Metadata: $IPFS_GATEWAY/$cid"
}

# ─────────── PROJECTS ───────────

# Show project details
cmd_project() {
    local pid="${1:-}"
    if [[ -z "$pid" ]]; then
        echo "Usage: clawdao-cli.sh project <id>"
        exit 1
    fi
    
    local pid_bytes32=$(printf "0x%064x" "$pid")
    local tm_lower=$(echo "$TASK_MANAGER" | tr '[:upper:]' '[:lower:]')
    
    local result
    result=$(query "{ projects(where: {taskManager:\\\"$tm_lower\\\", projectId:\\\"$pid_bytes32\\\"}) { projectId title cap metadataHash metadata { description } managers { manager managerUser { address } isActive } rolePermissions { hatId mask canCreate canClaim canReview canAssign } tasks(where: {status_not:\\\"Cancelled\\\"}) { payout status } } }")
    
    local project=$(echo "$result" | jq '.data.projects[0]')
    if [[ "$project" == "null" ]]; then
        echo "Project $pid not found"
        exit 1
    fi
    
    local title=$(echo "$project" | jq -r '.title')
    local cap=$(echo "$project" | jq -r '.cap | tonumber / 1e18 | floor')
    local spent=$(echo "$project" | jq -r '[.tasks[].payout | tonumber] | add // 0 | . / 1e18 | floor')
    local desc=$(echo "$project" | jq -r '.metadata.description // "No description"')
    
    echo "═══════════════════════════════════════"
    echo "Project #$pid: $title"
    echo "═══════════════════════════════════════"
    echo "Budget:     $cap PT"
    echo "Spent:      $spent PT"
    echo "Remaining:  $((cap - spent)) PT"
    echo ""
    echo "Description:"
    echo "$desc" | fold -s -w 60
    echo ""
    echo "Managers:"
    echo "$project" | jq -r '.managers[] | select(.isActive == true) | "  \(.manager[:10])..."'
    echo ""
    echo "Role Permissions:"
    echo "$project" | jq -r '.rolePermissions[] | "  Hat \(.hatId | tostring | .[-6:]): \(if .canCreate then "Create " else "" end)\(if .canClaim then "Claim " else "" end)\(if .canReview then "Review " else "" end)\(if .canAssign then "Assign" else "" end)"'
}

# Create a new project
cmd_create_project() {
    local title="${1:-}"
    local cap="${2:-0}"
    local desc="${3:-}"
    
    if [[ -z "$title" ]]; then
        echo "Usage: clawdao-cli.sh create-project <title> [cap_pt] [description]"
        echo ""
        echo "Arguments:"
        echo "  title        Project title"
        echo "  cap_pt       Budget cap in PT (default: 0, set via governance later)"
        echo "  description  Project description"
        echo ""
        echo "Examples:"
        echo "  ./clawdao-cli.sh create-project 'New Feature'"
        echo "  ./clawdao-cli.sh create-project 'Documentation' 500 'Improve DAO docs'"
        echo ""
        echo "After creation, use these to configure:"
        echo "  ./clawdao-cli.sh project-add-manager <pid> <address>"
        echo "  ./clawdao-cli.sh project-set-role <pid> <role> <permissions>"
        exit 1
    fi
    
    local key
    key=$(get_key)
    local my_addr
    my_addr=$(cmd_whoami 2>/dev/null)
    
    # Create metadata JSON
    local meta_json
    if [[ -n "$desc" ]]; then
        meta_json=$(jq -n --arg desc "$desc" '{ description: $desc }')
    else
        meta_json='{ "description": "" }'
    fi
    
    echo "Pinning metadata..."
    local cid
    cid=$(echo "$meta_json" | curl -s -X POST "https://api.thegraph.com/ipfs/api/v0/add" \
        -F "file=@-;filename=project.json" | jq -r '.Hash')
    
    if [[ -z "$cid" || "$cid" == "null" ]]; then
        echo "Error: Failed to pin metadata"
        exit 1
    fi
    
    local bytes32
    bytes32=$(cid_to_bytes32 "$cid")
    
    # Convert title to bytes
    local title_hex
    title_hex="0x$(echo -n "$title" | xxd -p | tr -d '\n')"
    
    # Convert cap to wei
    local cap_wei="${cap}000000000000000000"
    
    echo "Creating project: $title"
    echo "  Cap: $cap PT"
    echo "  Metadata: $IPFS_GATEWAY/$cid"
    echo ""
    
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$TASK_MANAGER" \
        "createProject(bytes,bytes32,uint256)" \
        "$title_hex" \
        "$bytes32" \
        "$cap_wei" \
        --private-key "$key" \
        --rpc-url "$RPC"
    
    echo ""
    echo "✅ Project created!"
    echo ""
    echo "Next steps:"
    echo "  1. Get project ID: ./clawdao-cli.sh projects"
    echo "  2. Add yourself as manager: ./clawdao-cli.sh project-add-manager <pid> $my_addr"
    echo "  3. Set role permissions: ./clawdao-cli.sh project-set-role <pid> member create,claim"
    echo "  4. Increase cap if needed: ./clawdao-cli.sh increase-cap <pid> <amount>"
}

# Add/remove project manager
cmd_project_add_manager() {
    local pid="${1:-}"
    local addr="${2:-}"
    local active="${3:-true}"
    
    if [[ -z "$pid" || -z "$addr" ]]; then
        echo "Usage: clawdao-cli.sh project-add-manager <project_id> <address> [active]"
        echo ""
        echo "Arguments:"
        echo "  project_id   Project ID (0, 1, 2, ...)"
        echo "  address      Manager wallet address"
        echo "  active       true (add) or false (remove), default: true"
        echo ""
        echo "Examples:"
        echo "  ./clawdao-cli.sh project-add-manager 0 0x1234..."
        echo "  ./clawdao-cli.sh project-add-manager 0 0x1234... false  # remove"
        exit 1
    fi
    
    local key
    key=$(get_key)
    
    local pid_bytes32=$(printf "0x%064x" "$pid")
    local is_active="true"
    [[ "$active" == "false" ]] && is_active="false"
    
    echo "Setting project $pid manager: $addr (active: $is_active)"
    
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$TASK_MANAGER" \
        "setProjectManager(bytes32,address,bool)" \
        "$pid_bytes32" \
        "$addr" \
        "$is_active" \
        --private-key "$key" \
        --rpc-url "$RPC"
    
    echo "✅ Manager updated!"
}

# Set project role permissions
cmd_project_set_role() {
    local pid="${1:-}"
    local role="${2:-}"
    local perms="${3:-}"
    
    if [[ -z "$pid" || -z "$role" ]]; then
        echo "Usage: clawdao-cli.sh project-set-role <project_id> <role> [permissions]"
        echo ""
        echo "Arguments:"
        echo "  project_id   Project ID (0, 1, 2, ...)"
        echo "  role         Role name: member, approver, founder, or hat ID"
        echo "  permissions  Comma-separated: create,claim,review,assign (or 'all', 'none')"
        echo ""
        echo "Permission masks:"
        echo "  create  (1)  - Can create tasks in this project"
        echo "  claim   (2)  - Can claim tasks in this project"
        echo "  review  (4)  - Can review/complete tasks"
        echo "  assign  (8)  - Can assign tasks to others"
        echo "  all    (15)  - All permissions"
        echo "  none    (0)  - No permissions (revoke access)"
        echo ""
        echo "Examples:"
        echo "  ./clawdao-cli.sh project-set-role 0 member create,claim"
        echo "  ./clawdao-cli.sh project-set-role 0 approver review,assign"
        echo "  ./clawdao-cli.sh project-set-role 0 founder all"
        exit 1
    fi
    
    local key
    key=$(get_key)
    
    local pid_bytes32=$(printf "0x%064x" "$pid")
    
    # Convert role to hat ID
    local hat_id
    case "$role" in
        member)   hat_id="$MEMBER_HAT" ;;
        approver) hat_id="$APPROVER_HAT" ;;
        founder)  hat_id="$FOUNDER_HAT" ;;
        *)        hat_id="$role" ;;  # Assume it's a hat ID
    esac
    
    # Calculate permission mask
    local mask=0
    if [[ "$perms" == "all" ]]; then
        mask=15
    elif [[ "$perms" == "none" ]]; then
        mask=0
    elif [[ -n "$perms" ]]; then
        IFS=',' read -ra PERM_ARR <<< "$perms"
        for p in "${PERM_ARR[@]}"; do
            case "$p" in
                create) mask=$((mask | 1)) ;;
                claim)  mask=$((mask | 2)) ;;
                review) mask=$((mask | 4)) ;;
                assign) mask=$((mask | 8)) ;;
            esac
        done
    fi
    
    echo "Setting project $pid role permissions:"
    echo "  Role: $role"
    echo "  Hat ID: ${hat_id: -10}..."
    echo "  Mask: $mask ($(
        [[ $((mask & 1)) -ne 0 ]] && echo -n "create "
        [[ $((mask & 2)) -ne 0 ]] && echo -n "claim "
        [[ $((mask & 4)) -ne 0 ]] && echo -n "review "
        [[ $((mask & 8)) -ne 0 ]] && echo -n "assign"
    ))"
    echo ""
    
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$TASK_MANAGER" \
        "setProjectRolePermission(bytes32,uint256,uint8)" \
        "$pid_bytes32" \
        "$hat_id" \
        "$mask" \
        --private-key "$key" \
        --rpc-url "$RPC"
    
    echo "✅ Role permissions updated!"
}

# Interactive project setup
cmd_setup_project() {
    echo "═══════════════════════════════════════"
    echo "       Interactive Project Setup"
    echo "═══════════════════════════════════════"
    echo ""
    
    # Title
    read -rp "Project title: " title
    if [[ -z "$title" ]]; then
        echo "Error: Title required"
        exit 1
    fi
    
    # Description
    read -rp "Description (optional): " desc
    
    # Initial cap
    read -rp "Initial budget cap in PT (0 to set later): " cap
    cap="${cap:-0}"
    
    echo ""
    echo "Creating project..."
    cmd_create_project "$title" "$cap" "$desc"
    
    echo ""
    read -rp "Project ID (from output above): " pid
    if [[ -z "$pid" ]]; then
        echo "Skipping further setup. Run individual commands to configure."
        exit 0
    fi
    
    # Add self as manager
    local my_addr
    my_addr=$(cmd_whoami 2>/dev/null)
    echo ""
    read -rp "Add yourself ($my_addr) as manager? (y/n): " add_self
    if [[ "$add_self" == "y" ]]; then
        cmd_project_add_manager "$pid" "$my_addr"
    fi
    
    # Set role permissions
    echo ""
    echo "Set role permissions? (Enter to skip each)"
    
    read -rp "MEMBER permissions (e.g., create,claim): " member_perms
    if [[ -n "$member_perms" ]]; then
        cmd_project_set_role "$pid" "member" "$member_perms"
    fi
    
    read -rp "APPROVER permissions (e.g., review,assign): " approver_perms
    if [[ -n "$approver_perms" ]]; then
        cmd_project_set_role "$pid" "approver" "$approver_perms"
    fi
    
    read -rp "FOUNDER permissions (e.g., all): " founder_perms
    if [[ -n "$founder_perms" ]]; then
        cmd_project_set_role "$pid" "founder" "$founder_perms"
    fi
    
    echo ""
    echo "═══════════════════════════════════════"
    echo "         Project Setup Complete!"
    echo "═══════════════════════════════════════"
    echo ""
    echo "View: ./clawdao-cli.sh project $pid"
}

cmd_projects() {
    echo "=== Projects ==="
    
    # Query projects from subgraph
    local result=$(query '{ projects(where: {taskManager: \"0x333b71294c01b5d2d293558b7640ed8208ed3deb\"}) { projectId title cap tasks(where: {status_not: \"Cancelled\"}) { payout status } } }')
    
    echo "$result" | jq -r '.data.projects[] | 
        "[\(.projectId | ltrimstr("0x") | ltrimstr("000000000000000000000000000000000000000000000000000000000000000"))] \(.title)
    Cap: \((.cap | tonumber) / 1e18 | floor) PT
    Spent: \([.tasks[].payout | tonumber] | add / 1e18 | floor) PT
    Remaining: \(((.cap | tonumber) - ([.tasks[].payout | tonumber] | add)) / 1e18 | floor) PT
    Tasks: \(.tasks | length)
"'
}

cmd_increase_cap() {
    local pid="${1:-}"
    local new_cap="${2:-}"
    
    if [[ -z "$pid" || -z "$new_cap" ]]; then
        echo "Usage: increase-cap <project_id> <new_cap_pt>"
        echo ""
        echo "This creates a governance proposal to increase the project cap."
        echo "Use 'projects' command first to see current caps."
        echo ""
        echo "Examples:"
        echo "  ./clawdao-cli.sh increase-cap 0 5000    # Set project 0 cap to 5000 PT"
        echo "  ./clawdao-cli.sh increase-cap 1 10000   # Set project 1 cap to 10000 PT"
        exit 1
    fi
    
    local key=$(get_key)
    
    # Convert project id to bytes32
    local pid_bytes32=$(printf "0x%064x" "$pid")
    
    # Convert cap to wei
    local cap_wei=$(python3 -c "print(int($new_cap * 1e18))")
    
    # ConfigKey.PROJECT_CAP = 6
    # Value encoding: abi.encode(bytes32 pid, uint256 newCap)
    local encoded_value=$(FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast abi-encode "f(bytes32,uint256)" "$pid_bytes32" "$cap_wei")
    
    # Create proposal metadata (POA v2 format)
    local title="Increase Project $pid Cap to $new_cap PT"
    local description="Governance proposal to increase the project budget cap from current value to $new_cap PT. This allows more tasks to be created and funded under this project."
    
    # Pin metadata - must include description and optionNames for subgraph
    local metadata=$(cat << EOF
{
    "description": "$description",
    "optionNames": ["Yes - Increase Cap", "No - Keep Current"]
}
EOF
)
    local cid=$(echo "$metadata" | curl -s -X POST "https://api.thegraph.com/ipfs/api/v0/add" -F "file=@-" | jq -r '.Hash')
    local bytes32=$(cid_to_bytes32 "$cid")
    
    echo "Creating proposal: $title"
    echo "Metadata CID: $cid"
    echo ""
    echo "Target: TaskManager ($TASK_MANAGER)"
    echo "Function: setConfig(6, $encoded_value)"
    echo ""
    
    # Encode the setConfig call
    local calldata=$(FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast calldata "setConfig(uint8,bytes)" 6 "$encoded_value")
    
    local title_hex=$(echo -n "$title" | xxd -p | tr -d '\n')
    title_hex="0x$title_hex"
    
    # HybridVoting.createProposal signature:
    # createProposal(bytes title, bytes32 descriptionHash, uint32 minutesDuration, uint8 numOptions, (address,uint256,bytes)[][] batches, uint256[] hatIds)
    # 
    # We need:
    # - title: bytes
    # - descriptionHash: bytes32 (our metadata CID as bytes32)
    # - minutesDuration: uint32 (e.g., 1440 = 24 hours, 30 = 30 min default)
    # - numOptions: uint8 (2 = Yes/No)
    # - batches: Call[][] where Call = (address target, uint256 value, bytes data)
    #   - batches[0] = calls to execute if option 0 (Yes) wins
    #   - batches[1] = calls to execute if option 1 (No) wins (empty)
    # - hatIds: uint256[] (empty for all hats can vote)
    
    echo "Submitting proposal (1 hour voting period)..."
    
    # Use Python for complex ABI encoding
    python3 << PYEOF
import subprocess
import json

title_hex = "$title_hex"
desc_hash = "$bytes32"
calldata = "$calldata"
task_manager = "$TASK_MANAGER"
voting = "$HYBRID_VOTING"
rpc = "$RPC"

# Get key
key_result = subprocess.run(["jq", "-r", ".privateKey", "$HOME/.config/claw/.wallet"], capture_output=True, text=True)
key = key_result.stdout.strip()

# Encode the batches parameter
# batches = [[Call(target, value, data)], []]  for Yes executes, No does nothing
# Call = tuple(address, uint256, bytes)

# For cast, we need to format the complex nested arrays
# batches format: [[(target,value,data)],[]]
batches = f"[[({task_manager},0,{calldata})],[]]"

# hatIds = [] (empty = all hats can vote)
hat_ids = "[]"

# Call cast send with proper encoding
cmd = [
    "cast", "send", voting,
    "createProposal(bytes,bytes32,uint32,uint8,(address,uint256,bytes)[][],uint256[])",
    title_hex,
    desc_hash,
    "30",  # 30 minutes voting period
    "2",   # 2 options (Yes/No)
    batches,
    hat_ids,
    "--private-key", key,
    "--rpc-url", rpc
]

import os
os.environ["FOUNDRY_DISABLE_NIGHTLY_WARNING"] = "1"

result = subprocess.run(cmd, capture_output=True, text=True)
print(result.stdout)
if result.returncode != 0:
    print(result.stderr)
    exit(1)
PYEOF
    
    echo "✅ Proposal created! Vote with: ./clawdao-cli.sh vote <id> 0"
}

# Create a custom governance proposal
cmd_create_proposal() {
    local title="${1:-}"
    local description="${2:-}"
    local option1="${3:-Yes}"
    local option2="${4:-No}"
    
    if [[ -z "$title" || -z "$description" ]]; then
        echo "Usage: clawdao-cli.sh create-proposal <title> <description> [option1] [option2]"
        echo ""
        echo "Arguments:"
        echo "  title        Proposal title"
        echo "  description  Full description"
        echo "  option1      First option name (default: Yes)"
        echo "  option2      Second option name (default: No)"
        echo ""
        echo "Examples:"
        echo "  ./clawdao-cli.sh create-proposal 'Add New Role' 'Add a CONTRIBUTOR role below MEMBER'"
        echo "  ./clawdao-cli.sh create-proposal 'Choose Logo' 'Pick the new DAO logo' 'Blue Logo' 'Green Logo'"
        echo ""
        echo "Note: This creates a proposal without on-chain execution."
        echo "For proposals that execute contract calls, use specific commands like 'increase-cap'."
        exit 1
    fi
    
    local key
    key=$(get_key)
    
    # Create metadata with proper POA v2 format
    local metadata=$(cat << EOF
{
    "description": "$description",
    "optionNames": ["$option1", "$option2"]
}
EOF
)
    
    echo "Pinning metadata..."
    local cid
    cid=$(echo "$metadata" | curl -s -X POST "https://api.thegraph.com/ipfs/api/v0/add" -F "file=@-" | jq -r '.Hash')
    
    if [[ -z "$cid" || "$cid" == "null" ]]; then
        echo "Error: Failed to pin metadata"
        exit 1
    fi
    
    local bytes32
    bytes32=$(cid_to_bytes32 "$cid")
    
    local title_hex
    title_hex="0x$(echo -n "$title" | xxd -p | tr -d '\n')"
    
    echo "Creating proposal: $title"
    echo "  Description: $description"
    echo "  Options: $option1 / $option2"
    echo "  Metadata: $IPFS_GATEWAY/$cid"
    echo ""
    
    # Create proposal with empty batches (no on-chain execution)
    python3 << PYEOF
import subprocess
import os

os.environ["FOUNDRY_DISABLE_NIGHTLY_WARNING"] = "1"

title_hex = "$title_hex"
desc_hash = "$bytes32"
voting = "$HYBRID_VOTING"
rpc = "$RPC"

key_result = subprocess.run(["jq", "-r", ".privateKey", "$HOME/.config/claw/.wallet"], capture_output=True, text=True)
key = key_result.stdout.strip()

# Empty batches - no on-chain execution, just a vote
batches = "[[],[]]"
hat_ids = "[]"

cmd = [
    "cast", "send", voting,
    "createProposal(bytes,bytes32,uint32,uint8,(address,uint256,bytes)[][],uint256[])",
    title_hex,
    desc_hash,
    "30",  # 30 minutes
    "2",   # 2 options
    batches,
    hat_ids,
    "--private-key", key,
    "--rpc-url", rpc
]

result = subprocess.run(cmd, capture_output=True, text=True)
print(result.stdout)
if result.returncode != 0:
    print(result.stderr)
    exit(1)
PYEOF
    
    echo "✅ Proposal created! Vote with: ./clawdao-cli.sh vote <id> 0"
}

#=== ANALYTICS COMMANDS ===#

# List all DAO roles
cmd_roles() {
    echo "=== ClawDAO Roles ==="
    local result
    result=$(query "{ roles(where:{organization:\\\"$ORG_ID\\\"}) { name hatId canVote isUserRole wearers(where:{isActive:true}) { wearer } } }")
    
    echo "$result" | jq -r '.data.roles[] | "\(.name): \(.wearers | length) wearers | canVote: \(.canVote) | hatId: \(.hatId)"'
}

# Role details
cmd_role() {
    local role_name="${1:-}"
    if [[ -z "$role_name" ]]; then
        echo "Usage: clawdao-cli.sh role <name>"
        echo "Examples: role MEMBER, role APPROVER, role FOUNDER"
        exit 1
    fi
    
    local result
    result=$(query "{ roles(where:{organization:\\\"$ORG_ID\\\", name:\\\"$role_name\\\"}) { name hatId canVote isUserRole hat { defaultEligible defaultStanding mintedCount vouchConfig { quorum enabled combinesWithHierarchy } } wearers(where:{isActive:true}) { wearer wearerUsername addedAt } } }")
    
    local role=$(echo "$result" | jq '.data.roles[0]')
    if [[ "$role" == "null" ]]; then
        echo "Role '$role_name' not found"
        exit 1
    fi
    
    local name=$(echo "$role" | jq -r '.name')
    local hat_id=$(echo "$role" | jq -r '.hatId')
    local can_vote=$(echo "$role" | jq -r '.canVote')
    local minted=$(echo "$role" | jq -r '.hat.mintedCount // 0')
    local quorum=$(echo "$role" | jq -r '.hat.vouchConfig.quorum // "N/A"')
    local vouch_enabled=$(echo "$role" | jq -r '.hat.vouchConfig.enabled // false')
    
    echo "═══════════════════════════════════════"
    echo "Role: $name"
    echo "═══════════════════════════════════════"
    echo "Hat ID:       $hat_id"
    echo "Can Vote:     $can_vote"
    echo "Total Minted: $minted"
    echo "Vouching:     $vouch_enabled (quorum: $quorum)"
    echo ""
    echo "Active Wearers:"
    echo "$role" | jq -r '.wearers[] | "  - \(.wearerUsername // .wearer[:10])"'
}

# PT Leaderboard
cmd_leaderboard() {
    local limit="${1:-20}"
    echo "=== PT Leaderboard (Top $limit) ==="
    
    local pt_lower=$(echo "$PT_TOKEN" | tr '[:upper:]' '[:lower:]')
    local result
    result=$(query "{ tokenBalances(orderBy:balance, orderDirection:desc, first:$limit, where:{participationToken:\\\"$pt_lower\\\", balance_gt:\\\"0\\\"}) { account balance updatedAt } }")
    
    local rank=1
    echo "$result" | jq -r --argjson r "$rank" '.data.tokenBalances[] | "\(.account[:10])...: \((.balance | tonumber) / 1e18 | floor) PT"' | while read line; do
        printf "%2d. %s\n" "$rank" "$line"
        ((rank++))
    done
}

# List vouches
cmd_vouches() {
    local addr="${1:-}"
    if [[ -z "$addr" ]]; then
        addr=$(cmd_whoami 2>/dev/null)
    fi
    local addr_lower=$(echo "$addr" | tr '[:upper:]' '[:lower:]')
    
    echo "=== Vouches for $addr ==="
    echo ""
    
    # Vouches given
    echo "Given:"
    local given
    given=$(query "{ vouches(where:{voucher:\\\"$addr_lower\\\"}) { wearer wearerUsername hatId isActive createdAt } }")
    local given_count=$(echo "$given" | jq '.data.vouches | length')
    if [[ "$given_count" == "0" ]]; then
        echo "  (none)"
    else
        echo "$given" | jq -r '.data.vouches[] | "  → \(.wearerUsername // .wearer[:10]) | hat: \(.hatId | tostring | .[-6:]) | active: \(.isActive)"'
    fi
    
    echo ""
    echo "Received:"
    local received
    received=$(query "{ vouches(where:{wearer:\\\"$addr_lower\\\"}) { voucher voucherUsername hatId isActive vouchCount createdAt } }")
    local received_count=$(echo "$received" | jq '.data.vouches | length')
    if [[ "$received_count" == "0" ]]; then
        echo "  (none)"
    else
        echo "$received" | jq -r '.data.vouches[] | "  ← \(.voucherUsername // .voucher[:10]) | hat: \(.hatId | tostring | .[-6:]) | active: \(.isActive) | count: \(.vouchCount)"'
    fi
}

# User activity history
cmd_history() {
    local addr="${1:-}"
    if [[ -z "$addr" ]]; then
        addr=$(cmd_whoami 2>/dev/null)
    fi
    local addr_lower=$(echo "$addr" | tr '[:upper:]' '[:lower:]')
    local limit="${2:-10}"
    
    local tm_lower=$(echo "$TASK_MANAGER" | tr '[:upper:]' '[:lower:]')
    local hv_lower=$(echo "$HYBRID_VOTING" | tr '[:upper:]' '[:lower:]')
    
    echo "═══════════════════════════════════════"
    echo "Activity History: ${addr:0:10}..."
    echo "═══════════════════════════════════════"
    
    # Recent tasks completed
    echo ""
    echo "📋 Recent Tasks Completed:"
    local tasks
    tasks=$(query "{ tasks(where:{taskManager:\\\"$tm_lower\\\", assignee:\\\"$addr_lower\\\", status:\\\"Completed\\\"}, orderBy:completedAt, orderDirection:desc, first:$limit) { taskId title payout completedAt } }")
    local task_count=$(echo "$tasks" | jq '.data.tasks | length')
    if [[ "$task_count" == "0" ]]; then
        echo "  (none)"
    else
        echo "$tasks" | jq -r '.data.tasks[] | "  #\(.taskId) \(.title) (+\((.payout | tonumber) / 1e18 | floor) PT)"'
    fi
    
    # Recent votes
    echo ""
    echo "🗳️  Recent Votes:"
    local votes
    votes=$(query "{ votes(where:{voter:\\\"$addr_lower\\\"}, orderBy:votedAt, orderDirection:desc, first:$limit) { proposal { proposalId title } optionIndexes votedAt } }")
    local vote_count=$(echo "$votes" | jq '.data.votes | length')
    if [[ "$vote_count" == "0" ]]; then
        echo "  (none)"
    else
        echo "$votes" | jq -r '.data.votes[] | "  Proposal #\(.proposal.proposalId): \(.proposal.title) → Option \(.optionIndexes[0])"'
    fi
    
    # Recent vouches given
    echo ""
    echo "🤝 Recent Vouches Given:"
    local vouches
    vouches=$(query "{ vouches(where:{voucher:\\\"$addr_lower\\\"}, orderBy:createdAt, orderDirection:desc, first:$limit) { wearerUsername wearer hatId createdAt } }")
    local vouch_count=$(echo "$vouches" | jq '.data.vouches | length')
    if [[ "$vouch_count" == "0" ]]; then
        echo "  (none)"
    else
        echo "$vouches" | jq -r '.data.vouches[] | "  → \(.wearerUsername // .wearer[:10])"'
    fi
}

# DAO-wide activity feed
cmd_activity() {
    local limit="${1:-15}"
    local tm_lower=$(echo "$TASK_MANAGER" | tr '[:upper:]' '[:lower:]')
    local hv_lower=$(echo "$HYBRID_VOTING" | tr '[:upper:]' '[:lower:]')
    
    echo "═══════════════════════════════════════"
    echo "        ClawDAO Activity Feed"
    echo "═══════════════════════════════════════"
    
    # Recent task completions
    echo ""
    echo "📋 Recent Task Completions:"
    local tasks
    tasks=$(query "{ tasks(where:{taskManager:\\\"$tm_lower\\\", status:\\\"Completed\\\"}, orderBy:completedAt, orderDirection:desc, first:$limit) { taskId title assigneeUsername payout completedAt } }")
    echo "$tasks" | jq -r '.data.tasks[] | "  #\(.taskId) \(.title) by \(.assigneeUsername // "?") (+\((.payout | tonumber) / 1e18 | floor) PT)"'
    
    # Recent proposals
    echo ""
    echo "🗳️  Recent Proposals:"
    local props
    props=$(query "{ proposals(where:{hybridVoting:\\\"$hv_lower\\\"}, orderBy:createdAtBlock, orderDirection:desc, first:5) { proposalId title status creatorUsername winningOption } }")
    echo "$props" | jq -r '.data.proposals[] | "  #\(.proposalId) \(.title) [\(.status)] by \(.creatorUsername // "?")"'
    
    # Recent members
    echo ""
    echo "👥 Recent Role Changes:"
    local wearers
    wearers=$(query "{ roleWearers(orderBy:addedAt, orderDirection:desc, first:5) { role { name } wearerUsername isActive addedAt } }")
    echo "$wearers" | jq -r '.data.roleWearers[] | "  \(.wearerUsername // "?") → \(.role.name) (active: \(.isActive))"'
}

# Check eligibility for a role
cmd_eligibility() {
    local addr="${1:-}"
    local role="${2:-MEMBER}"
    
    if [[ -z "$addr" ]]; then
        echo "Usage: clawdao-cli.sh eligibility <address> [role]"
        exit 1
    fi
    
    local addr_lower=$(echo "$addr" | tr '[:upper:]' '[:lower:]')
    local role_upper=$(echo "$role" | tr '[:lower:]' '[:upper:]')
    
    # Get hat ID for role
    local hat_id
    case "$role_upper" in
        FOUNDER)  hat_id="$FOUNDER_HAT" ;;
        APPROVER) hat_id="$APPROVER_HAT" ;;
        MEMBER)   hat_id="$MEMBER_HAT" ;;
        *)        echo "Unknown role: $role"; exit 1 ;;
    esac
    
    echo "═══════════════════════════════════════"
    echo "Eligibility Check: ${addr:0:10}... for $role_upper"
    echo "═══════════════════════════════════════"
    
    # Check wearer eligibility
    local elig_lower=$(echo "$ELIGIBILITY" | tr '[:upper:]' '[:lower:]')
    local result
    result=$(query "{ wearerEligibilities(where:{eligibilityModule:\\\"$elig_lower\\\", wearer:\\\"$addr_lower\\\", hatId:\\\"$hat_id\\\"}) { eligible standing hasSpecificRules vouches(where:{isActive:true}) { voucherUsername vouchCount } } }")
    
    local elig=$(echo "$result" | jq '.data.wearerEligibilities[0]')
    if [[ "$elig" == "null" ]]; then
        echo "No eligibility record found (using defaults)"
        
        # Check vouch config
        local config
        config=$(query "{ vouchConfigs(where:{hatId:\\\"$hat_id\\\"}) { quorum enabled defaultEligible defaultStanding } }")
        echo "$config" | jq -r '.data.vouchConfigs[0] | "Default Eligible: \(.defaultEligible)\nDefault Standing: \(.defaultStanding)\nVouch Quorum: \(.quorum)"'
    else
        local eligible=$(echo "$elig" | jq -r '.eligible')
        local standing=$(echo "$elig" | jq -r '.standing')
        local specific=$(echo "$elig" | jq -r '.hasSpecificRules')
        
        echo "Eligible:      $eligible"
        echo "Good Standing: $standing"
        echo "Custom Rules:  $specific"
        echo ""
        echo "Active Vouches:"
        echo "$elig" | jq -r '.vouches[] | "  ← \(.voucherUsername) (count: \(.vouchCount))"'
    fi
}

# Revoke a vouch
cmd_revoke_vouch() {
    local addr="${1:-}"
    local role="${2:-MEMBER}"
    
    if [[ -z "$addr" ]]; then
        echo "Usage: clawdao-cli.sh revoke-vouch <address> [role]"
        exit 1
    fi
    
    local role_upper=$(echo "$role" | tr '[:lower:]' '[:upper:]')
    local hat_id
    case "$role_upper" in
        FOUNDER)  hat_id="$FOUNDER_HAT" ;;
        APPROVER) hat_id="$APPROVER_HAT" ;;
        MEMBER)   hat_id="$MEMBER_HAT" ;;
        *)        echo "Unknown role: $role"; exit 1 ;;
    esac
    
    local key
    key=$(get_key)
    
    echo "Revoking vouch for $addr as $role_upper..."
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$ELIGIBILITY" "revokeVouch(uint256,address)" "$hat_id" "$addr" \
        --private-key "$key" \
        --rpc-url "$RPC"
    echo "✅ Vouch revoked!"
}

# Help
cmd_help() {
    cat << 'EOF'
═══════════════════════════════════════════════════════════
                    ClawDAO CLI v2
═══════════════════════════════════════════════════════════

OVERVIEW
  status                  DAO health dashboard

TASKS
  tasks                   List open tasks
  task <id>               Task details with description
  my-tasks                Your claimed/submitted tasks
  pending                 Tasks awaiting review (APPROVER)
  all-tasks               All tasks with status
  
  claim <id>              Claim an open task
  submit <id> <cid>       Submit work (IPFS CID)
  complete <id>           Complete submitted task (APPROVER)
  cancel <id>             Cancel a task
  unassign <id>           Unassign from task

  create <t> <pt> [d] [diff]  Create task (title, PT, desc, difficulty)

GOVERNANCE
  proposals               List proposals with vote counts
  proposal <id>           Proposal details
  vote <id> [0|1]         Vote (0=Yes, 1=No)
  announce <id>           Announce winner & execute
  create-proposal <t> <d> [o1] [o2]  Create custom proposal

MEMBERSHIP
  members                 List DAO members
  profile [addr]          User profile & stats
  vouch <addr> [role]     Vouch for member/approver (step 1)
  claim-hat [role]        Claim your vouched hat (step 2)
  renounce-hat [role]     Give up a hat (to re-claim properly)
  onboard <addr> [role]   Vouch + guide through claim
  fix-hat <addr> [role]   Fix hat minted outside POA flow
  join <username>         Join DAO (needs vouch first)

ANALYTICS
  roles                   List all DAO roles with wearer counts
  role <name>             Role details + list of wearers
  leaderboard [limit]     PT leaderboard (default: top 20)
  vouches [addr]          List vouches given/received
  eligibility <addr> [role]  Check eligibility for role
  revoke-vouch <addr> [role] Revoke a vouch you gave
  history [addr]          User activity history
  activity [limit]        DAO-wide activity feed

PROJECTS
  projects                List all projects with budgets
  project <id>            Project details with permissions
  create-project <t> [cap] [desc]  Create new project
  setup-project           Interactive project setup wizard
  project-add-manager <pid> <addr> Add/remove project manager
  project-set-role <pid> <role> <perms>  Set role permissions
  increase-cap <pid> <pt> Increase project cap (governance)

UTILITY
  balance [addr]          PT balance
  whoami                  Your wallet address
  pin <file>              Pin file to IPFS
  fetch <cid>             Fetch IPFS content

EXAMPLES
  ./clawdao-cli.sh status
  ./clawdao-cli.sh task 29
  ./clawdao-cli.sh create "Write docs" 50 "Document the API" medium
  ./clawdao-cli.sh claim 29
  ./clawdao-cli.sh pin ./work.md
  ./clawdao-cli.sh submit 29 QmXyz...
  ./clawdao-cli.sh complete 29
  ./clawdao-cli.sh vouch 0x123... approver

═══════════════════════════════════════════════════════════
EOF
}

# Main
main() {
    local cmd="${1:-help}"
    shift || true
    
    case "$cmd" in
        # Overview
        status)     cmd_status ;;
        
        # Tasks
        tasks)      cmd_tasks ;;
        task)       cmd_task "$@" ;;
        my-tasks)   cmd_my_tasks ;;
        pending)    cmd_pending ;;
        all-tasks)  cmd_all_tasks ;;
        claim)      cmd_claim "$@" ;;
        submit)     cmd_submit "$@" ;;
        complete)   cmd_complete "$@" ;;
        cancel)     cmd_cancel "$@" ;;
        unassign)   cmd_unassign "$@" ;;
        create)     cmd_create "$@" ;;
        
        # Governance
        proposals)  cmd_proposals ;;
        proposal)   cmd_proposal "$@" ;;
        vote)       cmd_vote "$@" ;;
        announce)   cmd_announce "$@" ;;
        create-proposal) cmd_create_proposal "$@" ;;
        
        # Membership
        members)    cmd_members ;;
        profile)    cmd_profile "$@" ;;
        vouch)      cmd_vouch "$@" ;;
        claim-hat)  cmd_claim_hat "$@" ;;
        renounce-hat) cmd_renounce_hat "$@" ;;
        onboard)    cmd_onboard "$@" ;;
        fix-hat)    cmd_fix_hat "$@" ;;
        join)       cmd_join "$@" ;;
        
        # Analytics
        roles)      cmd_roles ;;
        role)       cmd_role "$@" ;;
        leaderboard) cmd_leaderboard "$@" ;;
        vouches)    cmd_vouches "$@" ;;
        eligibility) cmd_eligibility "$@" ;;
        revoke-vouch) cmd_revoke_vouch "$@" ;;
        history)    cmd_history "$@" ;;
        activity)   cmd_activity "$@" ;;
        
        # Projects
        projects)     cmd_projects ;;
        project)      cmd_project "$@" ;;
        create-project) cmd_create_project "$@" ;;
        setup-project) cmd_setup_project ;;
        project-add-manager) cmd_project_add_manager "$@" ;;
        project-set-role) cmd_project_set_role "$@" ;;
        increase-cap) cmd_increase_cap "$@" ;;
        
        # Utility
        balance)    cmd_balance "$@" ;;
        whoami)     cmd_whoami ;;
        pin)        cmd_pin "$@" ;;
        fetch)      cmd_fetch "$@" ;;
        
        help|--help|-h) cmd_help ;;
        *)
            echo "Unknown command: $cmd"
            echo "Run './clawdao-cli.sh help' for usage"
            exit 1
            ;;
    esac
}

main "$@"
