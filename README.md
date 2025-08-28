# Lancache 25G Hardening Kit (Docker)

Production-ready configs and scripts to run **lancachenet/monolithic** on a 25 GbE host (512 GB RAM, 44 cores). 
Focus areas: **CPU balance, NIC offloads/RSS, THP compaction control, low-IO logging, safe DNS**, and a clean Docker setup.

> Use at your own risk; tune values for your environment. Tested on Ubuntu/Debian-class hosts.

---

## Contents

- `docker-compose.yml` – Host-network monolithic, bridge DNS (MTU 9200), persistent configs/logs
- `sysctl/sysctl.conf` – Kernel networking & writeback tuning
- `systemd/disable-thp.service` – Sets THP to `madvise` and disables proactive compaction
- `systemd/tune-25g.service` – Applies NIC offload/RSS/IRQ/RPS/MTU settings at boot
- `scripts/tune-25g.sh` – The tuning script used by the service
- `scripts/verify.sh` – One-shot health checks (CPU spread, NIC stats, sysctl)
- `configs/nginx/...` – Minimal Nginx overrides: disable access logs, cache log FDs
- `configs/bind/named.conf.options` – Quiet logging & safe ACLs

---

## Quick Start

> **Assumptions**
> - NIC: `enp4s0f0np0` (change in `scripts/tune-25g.sh` if different)
> - Jumbo frames supported end-to-end (switch ports allow ≥ 9200 MTU)
> - Host paths:
>   - `/lancache-root/lancache` – config root (bind+nginx)
>   - `/data/lancache/cache` – cache data
>   - `/var/log/lancache/logs` – app logs

### 1) Copy repo files

```bash
# Adjust the target root as needed
sudo rsync -av --delete configs/ /lancache-root/lancache/
sudo rsync -av --delete systemd/ /etc/systemd/system/
sudo rsync -av --delete sysctl/ /etc/
sudo rsync -av --delete scripts/ /usr/local/sbin/
sudo chmod +x /usr/local/sbin/*.sh
```

### 2) System services & kernel params

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now disable-thp.service
sudo systemctl enable --now tune-25g.service
sudo sysctl --system
```

### 3) Prepare directories

```bash
sudo mkdir -p /data/lancache/cache /var/log/lancache/logs
sudo mkdir -p /lancache-root/lancache/{bind,nginx}
sudo chown -R root:root /lancache-root/lancache
```

### 4) Configure `.env`

Create `.env` beside `docker-compose.yml` (see `.env.example`).

```dotenv
USE_GENERIC_CACHE=true
LANCACHE_IP=172.16.172.10
DNS_BIND_IP=172.16.172.10
UPSTREAM_DNS=8.8.8.8; 9.9.9.9; 1.1.1.1
CACHE_ROOT=/data/lancache
DATA_ROOT=/lancache-root/lancache

CACHE_DISK_SIZE=19000g
MIN_FREE_DISK=100g
CACHE_INDEX_SIZE=4750m
CACHE_MEM_SIZE=16000m
CACHE_SLICE_SIZE=4m
TZ=Asia/Dhaka
```

### 5) Deploy Docker

```bash
docker compose pull
docker compose up -d
```

### 6) Verify

```bash
sudo /usr/local/sbin/verify.sh

# DNS test
dig @${DNS_BIND_IP} google.com +short
```

---

## Troubleshooting

- **DNS `connection refused`** – In container, BIND must `listen-on any;` (already set) and your `ports:` mapping should target `${DNS_BIND_IP}:53`. Reload with `rndc reconfig` or restart the container.
- **One hot CPU/core (85%+)** – Ensure `disable-thp.service` is running (prevents `kcompactd0` spikes) and `tune-25g.service` applied (IRQ/RSS spread). Re-run `/usr/local/sbin/tune-25g.sh` after NIC name changes.
- **Drops on NIC** – Run `ethtool -S <iface>` and check `rx_missed|rx_no_buffer|rx_errors`. Increase queues (`ethtool -L`) or coalescing (`ethtool -C rx-usecs 75 tx-usecs 75`) carefully.
- **Jumbo frames** – MTU 9200 is set on host. Ensure switch ports support jumbo (>9000). Mismatch → fragmentation/drops.
- **High disk I/O** – Keep Nginx `access_log off;` and BIND logging minimal. Cache index size should match disk size (~250m per 1 TB).

---

## Security Notes

- DNS is **not** an open resolver: ACLs restrict query/recursion to private ranges.
- Use host firewalls as appropriate; this repo doesn’t install iptables rules.

---

## License

MIT
