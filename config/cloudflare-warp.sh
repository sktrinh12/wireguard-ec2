#!/bin/bash
# warp-doublehop.sh - Simple WireGuard → WARP double-hop for EC2

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    print_error "Run with sudo"
    exit 1
fi

setup() {
    print_status "Setting up WARP double-hop..."
    
    # Install dependencies
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y openresolv curl wget -qq
    
    # Install wgcf
    print_status "Installing wgcf..."
    ARCH=$(dpkg --print-architecture)
    wget -q -O /usr/local/bin/wgcf \
        "https://github.com/ViRb3/wgcf/releases/download/v2.2.30/wgcf_2.2.30_linux_${ARCH}"
    chmod +x /usr/local/bin/wgcf
    
    # Register with WARP
    cd /root
    rm -f wgcf-account.toml wgcf-profile.conf
    print_status "Registering with Cloudflare WARP..."
    wgcf register
    wgcf generate
    
    # Add policy routing to config
    awk '
    /^\[Interface\]/ { in_interface=1; print; next }
    /^\[Peer\]/ { 
        if (in_interface) {
            print "Table = off"
            print "PostUp = ip route add default dev wgcf table 1000"
            print "PostUp = ip rule add from 10.131.54.0/24 lookup 1000 pref 100"
            print "PostDown = ip rule del pref 100 2>/dev/null || true"
            print "PostDown = ip route flush table 1000 2>/dev/null || true"
            print ""
            in_interface=0
        }
        print
        next
    }
    { print }
    ' wgcf-profile.conf > /etc/wireguard/wgcf.conf
    chmod 600 /etc/wireguard/wgcf.conf
    
    # Ensure wg0 has IP forwarding
    if ! grep -q "net.ipv4.ip_forward=1" /etc/wireguard/wg0.conf 2>/dev/null; then
        sed -i '/^\[Interface\]/a PostUp = sysctl -w net.ipv4.ip_forward=1' /etc/wireguard/wg0.conf
    fi
    
    print_status "Setup complete!"
    echo ""
    print_info "Run: sudo $0 start"
}

start() {
    print_status "Starting double-hop mode..."
    wg-quick down wg0
    sleep 1
    wg-quick up wgcf
    sleep 1
    wg-quick up wg0
    
    echo ""
    print_status "✨ Double-hop ACTIVE (Laptop → EC2 → WARP)"
    echo ""
    
    status
}

stop() {
    print_status "Stopping double-hop mode..."
    wg-quick down wgcf 2>/dev/null || true
    
    echo ""
    print_status "✨ Back to one-hop mode (Laptop → EC2)"
    print_info "wg0 still running for direct connections"
    echo ""
}

status() {
    echo "══════════════════════════════════════════"
    
    if ip link show wgcf &>/dev/null; then
        print_status "WARP: ON"
        wg show wgcf | grep -E "(endpoint|handshake)" | sed 's/^/  /'
    else
        print_info "WARP: OFF (one-hop mode)"
    fi
    
    echo ""
    
    if ip link show wg0 &>/dev/null; then
        print_status "WG Server: RUNNING"
        PEERS=$(wg show wg0 peers 2>/dev/null | wc -l)
        echo "  Connected clients: $PEERS"
    else
        print_error "WG Server: STOPPED"
    fi
    
    echo ""
    
    # Test connection
    if command -v curl &>/dev/null; then
        TRACE=$(curl -s --max-time 3 https://cloudflare.com/cdn-cgi/trace 2>/dev/null || echo "")
        if [[ -n "$TRACE" ]]; then
            IP=$(echo "$TRACE" | grep "ip=" | cut -d= -f2)
            WARP=$(echo "$TRACE" | grep "warp=" | cut -d= -f2)
            echo "EC2 Direct: IP=$IP, WARP=$WARP"
        fi
    fi
    
    echo "══════════════════════════════════════════"
}

case "${1:-}" in
    setup)
        setup
        ;;
    start)
        start
        ;;
    stop)
        stop
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {setup|start|stop|status}"
        echo ""
        echo "  setup   - First time: install wgcf & register with WARP"
        echo "  start   - Enable double-hop (EC2 → WARP)"
        echo "  stop    - Disable double-hop (back to one-hop)"
        echo "  status  - Show current state"
        exit 1
        ;;
esac
