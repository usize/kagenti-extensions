#!/bin/bash
#
# AuthBridge Token Exchange Demo
# ==============================
# An interactive walkthrough demonstrating transparent token exchange
# using SPIFFE/SPIRE identities and Keycloak.
#
# Run this script and press ENTER to advance through each slide.
#

set -e

# Colors for pretty output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Box drawing characters
BOX_TL="╔"
BOX_TR="╗"
BOX_BL="╚"
BOX_BR="╝"
BOX_H="═"
BOX_V="║"

clear_screen() {
    clear
}

print_header() {
    local title="$1"
    local width=70
    local padding=$(( (width - ${#title} - 2) / 2 ))

    echo ""
    echo -e "${BLUE}${BOX_TL}$(printf '%*s' $width '' | tr ' ' "$BOX_H")${BOX_TR}${NC}"
    echo -e "${BLUE}${BOX_V}${NC}$(printf '%*s' $padding '')${BOLD}${CYAN}$title${NC}$(printf '%*s' $((width - padding - ${#title})) '')${BLUE}${BOX_V}${NC}"
    echo -e "${BLUE}${BOX_BL}$(printf '%*s' $width '' | tr ' ' "$BOX_H")${BOX_BR}${NC}"
    echo ""
}

print_slide_number() {
    local current=$1
    local total=$2
    echo -e "${DIM}[$current/$total]${NC}"
}

wait_for_enter() {
    echo ""
    echo -e "${DIM}Press ENTER to continue...${NC}"
    read -r
}

run_command() {
    local cmd="$1"
    local description="$2"

    echo -e "${YELLOW}$description${NC}"
    echo -e "${DIM}\$ $cmd${NC}"
    echo ""
    eval "$cmd"
}

# ============================================================================
# SLIDES
# ============================================================================

slide_intro() {
    clear_screen
    print_slide_number 1 12
    print_header "AuthBridge Token Exchange Demo"

    cat << 'EOF'
  This demo shows how AuthBridge a prototype demonstrating transparent token exchange
  for service-to-service authentication using:

    - SPIRE for workload identity (SPIFFE IDs)
    - Keycloak for token issuance and exchange 
    - Envoy sidecar for transparent request interception

  The Problem:
  ┌─────────────────────────────────────────────────────────────────┐
  │  Caller has token with:    aud: caller-identity                 │
  │  Target service expects:   aud: auth-target                     │
  │                                                                 │
  │  Without AuthBridge: Request fails (wrong audience)             │
  │  With AuthBridge:    Token exchanged transparently              │
  └─────────────────────────────────────────────────────────────────┘

EOF
    wait_for_enter
}

slide_architecture() {
    clear_screen
    print_slide_number 2 12
    print_header "Architecture Overview"

    cat << 'EOF'
  ┌─────────────────────────────────────────────────────────────────┐
  │                        AGENT POD                                │
  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
  │  │   Agent     │  │   SPIFFE    │  │   Client Registration   │  │
  │  │  (app)      │  │   Helper    │  │   (auto-registers)      │  │
  │  └──────┬──────┘  └─────────────┘  └─────────────────────────┘  │
  │         │                                                       │
  │         │ outbound request                                      │
  │         v                                                       │
  │  ┌─────────────────────────────────────────────────────────┐    │
  │  │              AuthBridge Sidecar                         │    │
  │  │  ┌──────────────┐    ┌──────────────────────────────┐   │    │
  │  │  │    Envoy     │───>│  Ext-Proc (token exchange)   │   │    │
  │  │  │  (iptables)  │<───│  exchanges token via Keycloak│   │    │
  │  │  └──────┬───────┘    └──────────────────────────────┘   │    │
  │  └─────────┼───────────────────────────────────────────────┘    │
  └────────────┼────────────────────────────────────────────────────┘
               │ request with NEW token (aud: auth-target)
               v
  ┌─────────────────────────────────────────────────────────────────┐
  │                     AUTH-TARGET POD                             │
  │              Validates token (expects aud: auth-target)         │
  └─────────────────────────────────────────────────────────────────┘

EOF
    wait_for_enter
}

slide_check_pods() {
    clear_screen
    print_slide_number 3 12
    print_header "Verify demo is running"

    echo -e "  Let's check that our demo pods are running:\n"

    run_command "kubectl get pods -n authbridge" "Pods in authbridge namespace:"

    wait_for_enter
}

slide_check_identity() {
    clear_screen
    print_slide_number 4 12
    print_header "SPIFFE Identity"

    cat << 'EOF'
  The agent pod automatically received a SPIFFE identity from SPIRE
  and registered with Keycloak using that identity as its client ID.

  The identity provider can be pluggable, -OR- we could federate.

EOF

    run_command "kubectl exec deployment/agent -n authbridge -c agent -- cat /shared/client-id.txt" "Agent's SPIFFE ID (Keycloak client ID):"

    wait_for_enter
}

slide_get_token() {
    clear_screen
    print_slide_number 5 12
    print_header "Exchange our spiffe ID for a JWT."

    cat << 'EOF'
  Now let's get a token from Keycloak using the agent's credentials.
  This simulates a caller obtaining a token to call the agent.

EOF

    echo -e "${YELLOW}Getting token from Keycloak...${NC}"
    echo -e "${DIM}\$ curl -sX POST .../token -d 'grant_type=client_credentials' ...${NC}\n"

    # Get the token
    TOKEN=$(kubectl exec deployment/agent -n authbridge -c agent -- sh -c '
        CLIENT_ID=$(cat /shared/client-id.txt)
        CLIENT_SECRET=$(cat /shared/client-secret.txt)
        curl -sX POST http://keycloak-service.keycloak.svc:8080/realms/demo/protocol/openid-connect/token \
          -d "grant_type=client_credentials" \
          -d "client_id=$CLIENT_ID" \
          -d "client_secret=$CLIENT_SECRET" | jq -r ".access_token"
    ')

    echo -e "Token: ${TOKEN}${NC}"

    # Store for later slides
    export DEMO_TOKEN="$TOKEN"

    wait_for_enter
}

slide_decode_original() {
    clear_screen
    print_slide_number 6 12
    print_header "Let's examine the token"

    kubectl exec deployment/agent -n authbridge -c agent -- sh -c '
        CLIENT_ID=$(cat /shared/client-id.txt)
        CLIENT_SECRET=$(cat /shared/client-secret.txt)
        TOKEN=$(curl -sX POST http://keycloak-service.keycloak.svc:8080/realms/demo/protocol/openid-connect/token \
          -d "grant_type=client_credentials" \
          -d "client_id=$CLIENT_ID" \
          -d "client_secret=$CLIENT_SECRET" | jq -r ".access_token")
        echo $TOKEN | cut -d"." -f2 | tr "_-" "/+" | { read p; echo "${p}=="; } | base64 -d 2>/dev/null | jq "{aud, azp, scope, iss}"
    '

    wait_for_enter
}

slide_call_target() {
    clear_screen
    print_slide_number 7 12
    print_header "Call auth-target, triggering token exchange"

    echo -e "${YELLOW}Calling auth-target service...${NC}"
    echo -e "${DIM}\$ curl -H \"Authorization: Bearer \$TOKEN\" http://auth-target-service:8081/test${NC}\n"

    RESULT=$(kubectl exec deployment/agent -n authbridge -c agent -- sh -c '
        CLIENT_ID=$(cat /shared/client-id.txt)
        CLIENT_SECRET=$(cat /shared/client-secret.txt)
        TOKEN=$(curl -sX POST http://keycloak-service.keycloak.svc:8080/realms/demo/protocol/openid-connect/token \
          -d "grant_type=client_credentials" \
          -d "client_id=$CLIENT_ID" \
          -d "client_secret=$CLIENT_SECRET" | jq -r ".access_token")
        curl -s -H "Authorization: Bearer $TOKEN" http://auth-target-service:8081/test
    ')

    echo -e "Response: ${GREEN}${BOLD}$RESULT${NC}"
    echo ""

    wait_for_enter
}

slide_examine_exchange() {
    clear_screen
    print_slide_number 8 12
    print_header "Exchange Logs"

    kubectl logs deployment/agent -n authbridge -c envoy-proxy 2>&1 | grep -E "(Token Exchange|Successfully)" | tail -10 || echo "(No recent exchange logs found - try running the call again)"

    kubectl logs deployment/auth-target -n authbridge 2>&1 | grep -E "(JWT Debug|Audience|authorized)" | tail -5 || echo "(Check auth-target logs)"

    wait_for_enter
}

slide_summary() {
    clear_screen
    print_slide_number 9 12
    print_header "What We Just Saw"

    cat << 'EOF'

  ┌─────────────────────────────────────────────────────────────────┐
  │                    TOKEN EXCHANGE FLOW                          │
  ├─────────────────────────────────────────────────────────────────┤
  │                                                                 │
  │   BEFORE EXCHANGE              AFTER EXCHANGE                   │
  │   ───────────────              ──────────────                   │
  │   aud: spiffe://../agent     --->   aud: auth-target            │
  │   scope: agent-spiffe        --->   scope: auth-target-aud      │
  │                                                                 │
  └─────────────────────────────────────────────────────────────────┘

EOF
    wait_for_enter
}

slide_limitations() {
    clear_screen
    print_slide_number 10 12
    print_header "Current Limitations"

    cat << 'EOF'

  What's missing from the demo:

  ┌─────────────────────────────────────────────────────────────────┐
  │                                                                 │
  │   NO DOWNSCOPING                                                │
  │   Exchanged tokens retain full permissions.                     │
  │   RFC 8693 supports scope reduction - not yet implemented.      │
  │                                                                 │
  ├─────────────────────────────────────────────────────────────────┤
  │                                                                 │
  │   NO DELEGATION CHAIN (ACT CLAIMS)                              │
  │   We do impersonation, not delegation.                          │
  │   No audit trail of: user -> agent -> tool                      │
  │                                                                 │
  ├─────────────────────────────────────────────────────────────────┤
  │                                                                 │
  │   SINGLE TRUST DOMAIN                                           │
  │   Only works within our cluster.                                │
  │   Can't exchange tokens for external APIs (GitHub, AWS, etc.)   │
  │                                                                 │
  ├─────────────────────────────────────────────────────────────────┤
  │                                                                 │
  │   NO USER CREDENTIAL STORAGE                                    │
  │   Users can't connect their accounts for agents to use.         │
  │   No vault for third-party tokens.                              │
  │                                                                 │
  └─────────────────────────────────────────────────────────────────┘

EOF
    wait_for_enter
}

slide_vision() {
    clear_screen
    print_slide_number 11 12
    print_header "The Vision: Three Personas"

    cat << 'EOF'

  ┌─────────────────────────────────────────────────────────────────┐
  │  PLATFORM ADMINISTRATOR                                         │
  ├─────────────────────────────────────────────────────────────────┤
  │  "I define policies out-of-band. Agents with role 'data-analyst'│
  │   can access Redshift. No per-agent credential provisioning."   │
  └─────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────┐
  │  AGENT DEVELOPER                                                │
  ├─────────────────────────────────────────────────────────────────┤
  │  "I write zero auth code. My agent gets a workload identity,    │
  │   AuthBridge handles token exchange transparently."             │
  │                                                                 │
  │   response = client.post("http://tool.mcp.local/query", ...)    │
  │   # No credentials. No OAuth. No refresh logic.                 │
  └─────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────┐
  │  END USER                                                       │
  ├─────────────────────────────────────────────────────────────────┤
  │  "I ask the agent to check my Redshift. It prompts me to login. │
  │   My credential is stored securely. The agent never sees it."   │
  └─────────────────────────────────────────────────────────────────┘

EOF
    wait_for_enter
}

slide_ideal_flow() {
    clear_screen
    print_slide_number 12 12
    print_header "Ideal Flow: User Delegation"

    cat << 'EOF'

  User: "Check what's in my Amazon Redshift"

  ┌──────────────────────────────────────────────────────────────────┐
  │ 1. Agent triggers OAuth -> User logs into AWS                    │
  │    Credential stored in Vault (bound to user)                    │
  └─────────────────────────────┬────────────────────────────────────┘
                                v
  ┌──────────────────────────────────────────────────────────────────┐
  │ 2. STS issues delegation token to Agent:                         │
  │    {sub: user, aud: agent, scope: vault:aws-redshift}            │
  └─────────────────────────────┬────────────────────────────────────┘
                                v
  ┌──────────────────────────────────────────────────────────────────┐
  │ 3. Agent -> Tool Server (token exchange builds chain):           │
  │    {sub: user, aud: tool-server, act: {sub: agent}}              │
  └─────────────────────────────┬────────────────────────────────────┘
                                v
  ┌──────────────────────────────────────────────────────────────────┐
  │ 4. Tool Server presents token to Vault:                          │
  │    Policy: "Is tool-server <- agent <- user authorized?"         │
  │    Yes -> Vault returns short-lived AWS credential               │
  └─────────────────────────────┬────────────────────────────────────┘
                                v
  ┌──────────────────────────────────────────────────────────────────┐
  │ 5. Tool Server queries Redshift -> Results returned to user      │
  └──────────────────────────────────────────────────────────────────┘

  Key properties:
    - Credential never leaves vault until final hop
    - Full delegation chain for audit: user -> agent -> tool
    - User can revoke access anytime

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    slide_intro
    slide_architecture
    slide_check_pods
    slide_check_identity
    slide_get_token
    slide_decode_original
    slide_call_target
    slide_examine_exchange
    slide_summary
    slide_limitations
    slide_vision
    slide_ideal_flow
}

main
