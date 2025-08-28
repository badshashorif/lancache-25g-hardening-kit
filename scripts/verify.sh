#!/usr/bin/env bash
set -euo pipefail

IF=${1:-enp4s0f0np0}

echo "=== Host summary ==="
echo "Iface: $IF"
ip -br link show "$IF" || true
echo

echo "=== CPU spread (mpstat) ==="
command -v mpstat >/dev/null && mpstat -P ALL 1 3 || echo "mpstat not installed"
echo

echo "=== NIC stats (ethtool -S) ==="
ethtool -S "$IF" | egrep -i 'rx_no_buffer|rx_missed|rx_errors|rx_dropped|tx_errors|tx_timeout|multicast|rx_packets|tx_packets' || true
echo

echo "=== Interrupts for $IF ==="
DRV=$(ethtool -i "$IF" 2>/dev/null | awk '/driver:/ {print $2}')
grep -iE "$IF|$DRV" /proc/interrupts || true
echo

echo "=== Sysctl highlights ==="
sysctl -n net.ipv4.tcp_congestion_control
sysctl -n net.core.netdev_max_backlog
sysctl -n net.core.rps_sock_flow_entries
sysctl -n vm.swappiness
