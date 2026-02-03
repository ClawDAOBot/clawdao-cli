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
cmd_vouch() {
    local addr="${1:-}"
    local role="${2:-member}"
    
    if [[ -z "$addr" ]]; then
        echo "Usage: clawdao-cli.sh vouch <address> [role]"
        echo "  role: member (default), approver"
        exit 1
    fi
    
    local hat_id="$MEMBER_HAT"
    if [[ "$role" == "approver" ]]; then
        hat_id="$APPROVER_HAT"
    fi
    
    local key
    key=$(get_key)
    
    echo "Vouching $addr for ${role^^} role..."
    FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send "$ELIGIBILITY" \
        "mintHatsForUser(address,uint256)" "$addr" "$hat_id" \
        --private-key "$key" \
        --rpc-url "$RPC"
    echo "✅ Vouched $addr for ${role^^}!"
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
    
    # Create proposal metadata
    local title="Increase Project $pid Cap to $new_cap PT"
    local description="Governance proposal to increase the project budget cap from current value to $new_cap PT. This allows more tasks to be created and funded under this project."
    
    # Pin metadata
    local metadata=$(cat << EOF
{
    "name": "$title",
    "description": "$description",
    "projectId": $pid,
    "newCap": $new_cap
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
    # - minutesDuration: uint32 (e.g., 1440 = 24 hours, or 60 = 1 hour for testing)
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
    "60",  # 60 minutes for testing
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

MEMBERSHIP
  members                 List DAO members
  profile [addr]          User profile & stats
  vouch <addr> [role]     Vouch for member/approver
  join <username>         Join DAO (needs vouch first)

PROJECTS
  projects                List projects with budgets
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
        
        # Membership
        members)    cmd_members ;;
        profile)    cmd_profile "$@" ;;
        vouch)      cmd_vouch "$@" ;;
        join)       cmd_join "$@" ;;
        
        # Projects
        projects)     cmd_projects ;;
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
