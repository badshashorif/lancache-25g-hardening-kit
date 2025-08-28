#!/usr/bin/env bash
set -euo pipefail

IF="enp4s0f0np0"      # 25G NIC (change if needed)
QUEUES="32"           # RSS queues (try 32/64 depending on NIC)
RXU=50; TXU=50        # coalescing usecs
MASK64="ffffffffffffffff"  # up to 64 CPUs

echo "[*] Tuning $IF (MTU/offload/queues/coalescing/IRQ/RPS/XPS)..."

# Jumbo MTU (ensure your switches allow jumbo frames)
ip link set dev "$IF" mtu 9200 || true

# Offloads (safe defaults for Docker/bridge/host)
ethtool -K "$IF" rx on tx on tso on gso on gro on lro off || true

# RSS queues
ethtool -L "$IF" combined "$QUEUES" || true

# Interrupt coalescing
ethtool -C "$IF" adaptive-rx on adaptive-tx on rx-usecs "$RXU" tx-usecs "$TXU" rx-frames 0 tx-frames 0 || true

# irqbalance and manual spread
systemctl enable --now irqbalance 2>/dev/null || true
DRV=$(ethtool -i "$IF" 2>/dev/null | awk '/driver:/ {print $2}')
CPU=2
for IRQ in $(grep -iE "$IF|$DRV" /proc/interrupts | awk -F: '{print $1}'); do
  # Create a mask for this CPU (works up to CPU 63)
  MASK=$(printf %x $((1<<CPU)))
  echo "$MASK" > /proc/irq/$IRQ/smp_affinity 2>/dev/null || true
  CPU=$(( (CPU+1) % 64 )); [ $CPU -lt 2 ] && CPU=2
done

# Software fan-out
sysctl -w net.core.rps_sock_flow_entries=65536 >/dev/null
for f in /sys/class/net/$IF/queues/rx-*/rps_flow_cnt; do echo 4096 > "$f" 2>/dev/null || true; done
for q in /sys/class/net/$IF/queues/rx-*; do echo "$MASK64" > "$q"/rps_cpus 2>/dev/null || true; done
for q in /sys/class/net/$IF/queues/tx-*; do echo "$MASK64" > "$q"/xps_cpus 2>/dev/null || true; done

echo "[OK] 25G tuning applied on $IF"
