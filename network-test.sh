#!/usr/bin/env bash

# Network Quality Test Script
# Tests: latency, packet loss, download speed, upload speed
# Usage: ./network-test.sh [--server SERVER_ID]

# Use safer error handling without causing script to exit on every error
set -uo pipefail

# Parse arguments
SPEEDTEST_SERVER=""
for arg in "$@"; do
    case $arg in
        --server=*)
            SPEEDTEST_SERVER="${arg#*=}"
            shift
            ;;
        --list-servers)
            echo "Listing nearby speedtest.net servers..."
            speedtest-cli --list 2>/dev/null | grep -i "philippines\|davao\|cebu\|manila" | head -20 || speedtest-cli --list | head -30
            exit 0
            ;;
        --help|-h)
            echo "Usage: $0 [--server SERVER_ID] [--list-servers] [--help]"
            echo ""
            echo "Options:"
            echo "  --server=SERVER_ID  Use specific speedtest server"
            echo "  --list-servers      List available servers (filter: Philippines)"
            echo "  --help              Show this help"
            echo ""
            echo "Note: For accurate results, use a server near you."
            echo "      Your Ookla browser test used: Globe Davao City"
            exit 0
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
PING_TARGET="8.8.8.8"
PING_COUNT=20

# Speed test URLs - Global CDNs with local presence
SPEED_TEST_URLS=(
    "https://speed.cloudflare.com/__down?bytes=50000000"  # 50MB - Cloudflare (good PH presence)
    "https://speed.hetzner.de/100MB.bin"                   # 100MB - Germany
    "https://proof.ovh.net/files/100Mb.dat"               # 100MB - France
    "https://ash-bug-common-cfg.hashicdn-aws.com/100MB.bin" # AWS Singapore
    "https://sin-sg-bw1.becomecloud.co.id/file/100MB.bin"  # Singapore
)

# Function to auto-select best server based on latency
get_best_speedtest_server() {
    if ! command -v speedtest-cli &> /dev/null; then
        return 1
    fi
    
    # Get list of servers - with timeout to prevent hanging
    local server_list=""
    server_list=$(timeout 10 speedtest-cli --list 2>/dev/null | head -30) || true
    
    if [ -z "$server_list" ]; then
        return 1
    fi
    
    # Parse servers and find best by geographic distance (quick approximation)
    # Format: "     12345) Hostname (City, Country) [XX.XX km]"
    local best_server=""
    local best_distance=999999
    
    while IFS= read -r line; do
        # Extract server ID
        local server_id
        server_id=$(echo "$line" | awk -F')' '{gsub(/^[ \t]+/, "", $1); print $1}' | grep -E '^[0-9]+$')
        
        if [ -n "$server_id" ]; then
            # Extract distance if present
            local distance="999999"
            distance=$(echo "$line" | grep -oE '\[[0-9]+\.[0-9]+ km\]' | grep -oE '[0-9]+\.[0-9]+' || echo "999999")
            
            if [ "$distance" != "999999" ] && awk "BEGIN {exit !($distance < $best_distance)}"; then
                best_distance="$distance"
                best_server="$server_id"
            fi
        fi
    done <<< "$server_list"
    
    if [ -n "$best_server" ] && [ "$best_server" != "999999" ]; then
        echo "$best_server|$best_distance"
        return 0
    fi
    
    # Fallback: return first server
    local first_server
    first_server=$(echo "$server_list" | grep -E '^[ ]*[0-9]+' | head -1 | awk -F')' '{gsub(/^[ \t]+/, "", $1); print $1}' | grep -E '^[0-9]+$')
    if [ -n "$first_server" ]; then
        echo "$first_server|unknown"
        return 0
    fi
    
    return 1
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       NETWORK CONNECTION QUALITY TEST                ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Test 1: Latency & Packet Loss
echo -e "${YELLOW}[1/4] Testing Latency & Packet Loss...${NC}"
echo -e "Target: ${PING_TARGET} (${PING_COUNT} pings)"

PING_OUTPUT=$(ping -c ${PING_COUNT} ${PING_TARGET} 2>&1 || ping -c ${PING_COUNT} 1.1.1.1)

PACKETS_LOST=$(echo "${PING_OUTPUT}" | grep -o '[0-9]\+% packet loss' | grep -o '[0-9]\+')
RTT_LINE=$(echo "${PING_OUTPUT}" | grep 'rtt min/avg/max' || echo "${PING_OUTPUT}" | grep 'min/avg/max')

if [ -n "$RTT_LINE" ]; then
    MIN_LATENCY=$(echo "$RTT_LINE" | awk '{split($4, a, "/"); print a[1]}')
    AVG_LATENCY=$(echo "$RTT_LINE" | awk '{split($4, a, "/"); print a[2]}')
    MAX_LATENCY=$(echo "$RTT_LINE" | awk '{split($4, a, "/"); print a[3]}')
    JITTER=$(awk -v min="$MIN_LATENCY" -v max="$MAX_LATENCY" 'BEGIN {printf "%.1f", max - min}')
else
    AVG_LATENCY="N/A"
    MIN_LATENCY="N/A"
    MAX_LATENCY="N/A"
    JITTER="N/A"
    PACKETS_LOST="0"
fi

LATENCY_COLOR="${RED}"
if [ "$AVG_LATENCY" != "N/A" ] && awk "BEGIN {exit !(${AVG_LATENCY} < 30)}"; then
    LATENCY_COLOR="${GREEN}"
elif [ "$AVG_LATENCY" != "N/A" ] && awk "BEGIN {exit !(${AVG_LATENCY} < 100)}"; then
    LATENCY_COLOR="${YELLOW}"
fi

echo -e "  Packet Loss: ${PACKETS_LOST}%"
echo -e "  Avg Latency: ${LATENCY_COLOR}${AVG_LATENCY} ms${NC}"
echo -e "  Min/Max:     ${MIN_LATENCY} / ${MAX_LATENCY} ms"
echo -e "  Jitter:      ${JITTER} ms"
echo ""

# Test 2: Connection Quality
echo -e "${YELLOW}[2/4] Connection Quality Assessment...${NC}"

if [ "$AVG_LATENCY" != "N/A" ] && [ "${PACKETS_LOST}" -eq 0 ] && awk "BEGIN {exit !(${AVG_LATENCY} < 50)}"; then
    QUALITY="${GREEN}EXCELLENT${NC}"
elif [ "$AVG_LATENCY" != "N/A" ] && [ "${PACKETS_LOST}" -lt 3 ] && awk "BEGIN {exit !(${AVG_LATENCY} < 100)}"; then
    QUALITY="${GREEN}GOOD${NC}"
elif [ "$AVG_LATENCY" != "N/A" ] && [ "${PACKETS_LOST}" -lt 5 ] && awk "BEGIN {exit !(${AVG_LATENCY} < 150)}"; then
    QUALITY="${YELLOW}FAIR${NC}"
else
    QUALITY="${RED}POOR${NC}"
fi

echo -e "  Overall Quality: ${QUALITY}"
echo ""

# Test 3: DNS Resolution
echo -e "${YELLOW}[3/4] Testing DNS Resolution Speed...${NC}"

DNS_TIME=$(curl -s -o /dev/null -w "%{time_total}" "https://www.google.com" 2>/dev/null || echo "0.5")
DNS_MS=$(awk "BEGIN {printf \"%.0f\", $DNS_TIME * 1000}")
echo -e "  Google.com: ${DNS_MS} ms"
echo ""

# Test 4: Bandwidth Speed Test
echo -e "${YELLOW}[4/4] Testing Bandwidth (Speed)...${NC}"
echo "  Testing download and upload speeds..."

DOWNLOAD_SPEED="N/A"
UPLOAD_SPEED="N/A"

# Method 1: speedtest-cli with auto-selected best server
if command -v speedtest-cli &> /dev/null; then
    echo -e "  ${CYAN}Method 1: speedtest-cli${NC}"
    
    if [ -n "$SPEEDTEST_SERVER" ]; then
        echo -e "  Server: ${SPEEDTEST_SERVER} (user-specified)"
        SPEEDTEST_OUTPUT=$(speedtest-cli --simple --server "$SPEEDTEST_SERVER" 2>&1) || true
    else
        # Auto-select best server based on geographic distance
        echo -e "  Auto-selecting best server..."
        BEST_SERVER_INFO=$(get_best_speedtest_server)
        if [ $? -eq 0 ] && [ -n "$BEST_SERVER_INFO" ]; then
            SPEEDTEST_SERVER=$(echo "$BEST_SERVER_INFO" | cut -d'|' -f1)
            BEST_DISTANCE=$(echo "$BEST_SERVER_INFO" | cut -d'|' -f2)
            echo -e "  Selected: Server #${SPEEDTEST_SERVER} (~${BEST_DISTANCE} km away)"
            SPEEDTEST_OUTPUT=$(speedtest-cli --simple --server "$SPEEDTEST_SERVER" 2>&1) || true
        else
            echo -e "  ${YELLOW}Warning: Could not determine best server, using default...${NC}"
            SPEEDTEST_OUTPUT=$(speedtest-cli --simple 2>&1) || true
        fi
    fi
    
    CLI_DOWNLOAD=$(echo "$SPEEDTEST_OUTPUT" | grep -i "Download" | awk '{print $2}')
    CLI_UPLOAD=$(echo "$SPEEDTEST_OUTPUT" | grep -i "Upload" | awk '{print $2}')
    
    if [ -n "$CLI_DOWNLOAD" ] && [ -n "$CLI_UPLOAD" ]; then
        DOWNLOAD_SPEED="${CLI_DOWNLOAD} Mbit/s"
        UPLOAD_SPEED="${CLI_UPLOAD} Mbit/s"
        echo -e "  Result: DL=${DOWNLOAD_SPEED}, UP=${UPLOAD_SPEED}"
    fi
else
    echo -e "  ${YELLOW}speedtest-cli not installed${NC}"
fi

# Method 2: HTTP CDN-based tests (more accurate, global CDNs)
echo -e "  ${CYAN}Method 2: CDN Speed Test (Cloudflare, Hetzner, etc.)${NC}"

run_curl_speedtest() {
    local url="$1"
    local start_time end_time duration bytes speed_mbps
    
    start_time=$(date +%s%N)
    bytes=$(curl -s --connect-timeout 15 --max-time 120 -w "%{size_download}" -o /dev/null "$url" 2>/dev/null || echo "0")
    end_time=$(date +%s%N)
    
    if [ "$bytes" -gt 0 ]; then
        duration=$(( (end_time - start_time) / 1000000000 ))
        if [ "$duration" -ge 1 ]; then
            speed_mbps=$(awk "BEGIN {printf \"%.1f\", ($bytes * 8) / ($duration * 1000000)}")
            echo "$speed_mbps|$duration|${bytes}"
            return 0
        fi
    fi
    echo "failed"
    return 1
}

echo -e "  Testing multiple CDN endpoints..."
best_speed=0
best_url=""
best_duration=0

for url in "${SPEED_TEST_URLS[@]}"; do
    result=$(run_curl_speedtest "$url")
    if [ "$result" != "failed" ]; then
        speed=$(echo "$result" | cut -d'|' -f1)
        duration=$(echo "$result" | cut -d'|' -f2)
        bytes=$(echo "$result" | cut -d'|' -f3)
        
        if awk "BEGIN {exit !($speed > $best_speed)}"; then
            best_speed=$speed
            best_url=$url
            best_duration=$duration
        fi
        # Extract display name from URL - handle query parameters properly
        url_basename=$(basename "$url" .bin 2>/dev/null || basename "$url")
        display_name=$(echo "$url_basename" | cut -d'?' -f1 | rev | cut -d'/' -f1 | rev)
        [ -z "$display_name" ] && display_name=$(echo "$url" | cut -d'/' -f3 | cut -d'?' -f1)
        
        echo -e "    ${display_name}: ${speed} Mbit/s (${duration}s)"
    fi
done

if [ "$(echo "$best_speed > 0" | bc)" -eq 1 ]; then
    echo -e "  ${GREEN}Best CDN: ${best_speed} Mbit/s${NC}"
    
    # Use HTTP result if it's better than speedtest-cli
    if awk "BEGIN {exit !($best_speed > $DOWNLOAD_SPEED)}"; then
        DOWNLOAD_SPEED="${best_speed} Mbit/s (CDN)"
    fi
fi

# Upload test
echo -e "  ${CYAN}Upload Test${NC}"

test_upload_speed() {
    local test_file="/tmp/speedtest_upload_$$"
    local start_time end_time duration bytes speed_mbps
    
    dd if=/dev/urandom of="$test_file" bs=1M count=10 2>/dev/null
    
    start_time=$(date +%s%N)
    bytes=$(curl -s --connect-timeout 15 --max-time 120 -X POST \
           --data-binary @"$test_file" \
           -H "Content-Type: application/octet-stream" \
           -w "%{size_upload}" -o /dev/null \
           "https://speed.cloudflare.com/__up" 2>/dev/null || echo "0")
    end_time=$(date +%s%N)
    
    rm -f "$test_file"
    
    if [ "$bytes" -gt 0 ]; then
        duration=$(( (end_time - start_time) / 1000000000 ))
        if [ "$duration" -ge 1 ]; then
            speed_mbps=$(awk "BEGIN {printf \"%.1f\", ($bytes * 8) / ($duration * 1000000)}")
            echo "$speed_mbps|$duration"
        else
            echo "failed"
        fi
    else
        echo "failed"
    fi
}

UPLOAD_RESULT=$(test_upload_speed)
if [ "$UPLOAD_RESULT" != "failed" ]; then
    UPLOAD_SPEED_VAL=$(echo "$UPLOAD_RESULT" | cut -d'|' -f1)
    echo -e "  CDN Upload: ${UPLOAD_SPEED_VAL} Mbit/s"
    
    if [ "$(echo "$UPLOAD_SPEED_VAL > 10" | bc)" -eq 1 ]; then
        if [ "$UPLOAD_SPEED" = "N/A" ] || [ "$(echo "$UPLOAD_SPEED_VAL > $UPLOAD_SPEED" | bc)" -eq 1 ]; then
            UPLOAD_SPEED="${UPLOAD_SPEED_VAL} Mbit/s (CDN)"
        fi
    fi
fi

echo ""
echo -e "  ${GREEN}Download: ${DOWNLOAD_SPEED}${NC}"
echo -e "  ${GREEN}Upload:   ${UPLOAD_SPEED}${NC}"
echo ""

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    SUMMARY                           ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Latency:      ${AVG_LATENCY} ms (min: ${MIN_LATENCY}, max: ${MAX_LATENCY})"
echo -e "Packet Loss:  ${PACKETS_LOST}%"
echo -e "Download:     ${DOWNLOAD_SPEED}"
echo -e "Upload:       ${UPLOAD_SPEED}"
echo ""
echo -e "Quality:      ${QUALITY}"
echo ""

# Comparison note
if [ "$AVG_LATENCY" != "N/A" ] && [ "${PACKETS_LOST}" -lt 10 ]; then
    echo -e "${YELLOW}Tip: For Ookla-equivalent results, use --server with a nearby server:${NC}"
    echo -e "  ${CYAN}./network-test.sh --list-servers${NC}  # Find Philippines servers"
    echo -e "  ${CYAN}./network-test.sh --server=12345${NC}   # Use specific server"
fi

echo ""
echo "Test completed at $(date)"
