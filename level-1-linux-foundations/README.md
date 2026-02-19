# Level 1: Linux Foundations for SRE

*"You can't troubleshoot what you don't understand."*

**Time estimate: 20-25 hours**

---

## 1.1 The Linux Boot Process — What Happens Before You See a Prompt

Understanding the boot process is essential because production outages often happen at boot time — a bad kernel, a corrupt filesystem, or a misconfigured service.

### The Boot Sequence

```
Power On
   │
   ▼
┌──────────┐
│ BIOS/UEFI│  Hardware init, POST, find bootloader
└────┬─────┘
     │
     ▼
┌──────────┐
│ GRUB2    │  Load kernel + initramfs into RAM
└────┬─────┘
     │
     ▼
┌──────────┐
│ Kernel   │  Hardware detection, mount root filesystem
└────┬─────┘
     │
     ▼
┌──────────┐
│ systemd  │  PID 1 — starts all services (targets/units)
│ (init)   │
└────┬─────┘
     │
     ▼
┌──────────┐
│ Login    │  getty / SSH / display manager
│ Prompt   │
└──────────┘
```

### Key Commands for Boot Troubleshooting

```bash
# View boot messages (kernel ring buffer)
dmesg | less
dmesg -T                          # Human-readable timestamps
dmesg --level=err,warn            # Only errors and warnings

# View systemd boot log
journalctl -b                     # Current boot
journalctl -b -1                  # Previous boot
journalctl --list-boots            # List all boots

# Measure boot time
systemd-analyze                   # Total boot time
systemd-analyze blame             # Slowest units
systemd-analyze critical-chain    # Critical path

# GRUB configuration
cat /etc/default/grub
cat /boot/grub/grub.cfg           # Generated — don't edit directly
```

**Lab: [lab-1.1-boot-analysis.sh](labs/lab-1.1-boot-analysis.sh)**

---

## 1.2 Systemd — The Service Manager You Must Master

Systemd controls everything that runs on a modern Linux system. As an SRE, you'll interact with it daily.

### Essential systemctl Commands

```bash
# ──────────────────────────────────────
# Service Lifecycle
# ──────────────────────────────────────
systemctl start nginx              # Start a service
systemctl stop nginx               # Stop a service
systemctl restart nginx            # Stop + Start
systemctl reload nginx             # Reload config without restart
systemctl enable nginx             # Start on boot
systemctl disable nginx            # Don't start on boot
systemctl enable --now nginx       # Enable AND start immediately
systemctl mask nginx               # Prevent service from starting entirely
systemctl unmask nginx             # Undo mask

# ──────────────────────────────────────
# Status and Investigation
# ──────────────────────────────────────
systemctl status nginx             # Current status + recent logs
systemctl is-active nginx          # Just "active" or "inactive"
systemctl is-enabled nginx         # "enabled" or "disabled"
systemctl is-failed nginx          # "failed" or not
systemctl show nginx               # All properties
systemctl show nginx -p MainPID    # Specific property
systemctl cat nginx                # Show the unit file

# ──────────────────────────────────────
# System-Wide
# ──────────────────────────────────────
systemctl list-units               # All loaded units
systemctl list-units --failed      # Failed units only
systemctl list-unit-files          # All unit files (enabled/disabled)
systemctl list-dependencies nginx  # Dependency tree
systemctl daemon-reload            # Reload unit files after editing
```

### Understanding Unit Files

```bash
# Where unit files live (in priority order):
# /etc/systemd/system/          ← Admin overrides (highest priority)
# /run/systemd/system/          ← Runtime generated
# /usr/lib/systemd/system/      ← Package defaults (lowest priority)

# Example: Custom service unit file
cat <<'EOF' | sudo tee /etc/systemd/system/myapp.service
[Unit]
Description=My Application
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=appuser
Group=appgroup
WorkingDirectory=/opt/myapp
ExecStart=/opt/myapp/bin/server --port 8080
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=3
StandardOutput=journal
StandardError=journal
SyslogIdentifier=myapp

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/myapp/data

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now myapp
```

### Journalctl — Reading Logs Like a Pro

```bash
# ──────────────────────────────────────
# Basic Log Viewing
# ──────────────────────────────────────
journalctl                          # All logs
journalctl -f                       # Follow (like tail -f)
journalctl -n 50                    # Last 50 lines
journalctl --no-pager               # Don't paginate

# ──────────────────────────────────────
# Filtering
# ──────────────────────────────────────
journalctl -u nginx                 # Specific unit
journalctl -u nginx -u php-fpm     # Multiple units
journalctl -p err                   # Priority: emerg,alert,crit,err
journalctl -p warning               # Warning and above
journalctl _PID=1234                # Specific PID
journalctl _UID=1000                # Specific user

# ──────────────────────────────────────
# Time-Based Filtering (CRITICAL for incident response)
# ──────────────────────────────────────
journalctl --since "2024-01-15 14:00:00"
journalctl --since "1 hour ago"
journalctl --since "10 minutes ago"
journalctl --since "yesterday" --until "today"
journalctl --since "2024-01-15" --until "2024-01-16"

# ──────────────────────────────────────
# Output Formats
# ──────────────────────────────────────
journalctl -u nginx -o json-pretty  # JSON (great for scripts)
journalctl -u nginx -o short-iso    # ISO timestamps
journalctl -u nginx -o verbose      # All fields

# ──────────────────────────────────────
# Disk Usage
# ──────────────────────────────────────
journalctl --disk-usage             # How much space logs use
sudo journalctl --vacuum-size=500M  # Shrink to 500MB
sudo journalctl --vacuum-time=7d    # Keep only 7 days
```

**Lab: [lab-1.2-service-management.sh](labs/lab-1.2-service-management.sh)**

---

## 1.3 Filesystem and Disk Management

### Understanding the Filesystem Hierarchy

```bash
# Critical directories an SRE must know:
/               # Root — everything starts here
├── /boot       # Kernel, initramfs, GRUB — if full, system won't update/boot
├── /etc        # Configuration files — backup this before changes
├── /var        # Variable data — logs, databases, mail — fills up often!
│   ├── /var/log        # System and application logs
│   ├── /var/lib        # Application state (Docker images, databases)
│   └── /var/tmp        # Persistent temp files
├── /tmp        # Temporary files — cleared on reboot
├── /home       # User home directories
├── /opt        # Third-party software
├── /proc       # Virtual filesystem — kernel and process info
├── /sys        # Virtual filesystem — hardware and driver info
├── /dev        # Device files
└── /run        # Runtime data (PIDs, sockets) — tmpfs
```

### Disk Commands Every SRE Needs

```bash
# ──────────────────────────────────────
# Disk Space
# ──────────────────────────────────────
df -h                              # Disk usage (human-readable)
df -i                              # Inode usage (can run out even with free space!)
df -hT                             # Include filesystem type

# ──────────────────────────────────────
# Directory Size
# ──────────────────────────────────────
du -sh /var/log                    # Size of a directory
du -sh /var/log/*                  # Size of each item in directory
du -sh /* 2>/dev/null | sort -rh   # Largest top-level directories
du -sh /var/log/* | sort -rh | head -10  # Top 10 largest in /var/log

# ──────────────────────────────────────
# Find Large Files
# ──────────────────────────────────────
find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null  # Files > 100MB
find /var -type f -size +50M -printf '%s %p\n' | sort -rn | head -20

# ──────────────────────────────────────
# Block Devices and Partitions
# ──────────────────────────────────────
lsblk                             # Block device tree
lsblk -f                          # Show filesystem types
blkid                             # Block device attributes
fdisk -l                          # Partition tables

# ──────────────────────────────────────
# Mount Management
# ──────────────────────────────────────
mount | column -t                  # Current mounts
cat /etc/fstab                     # Persistent mount configuration
findmnt                            # Mount tree
findmnt -t ext4                    # Only ext4 mounts

# ──────────────────────────────────────
# Filesystem Health
# ──────────────────────────────────────
sudo fsck -n /dev/sda1             # Check without fixing (-n = dry run)
sudo tune2fs -l /dev/sda1          # ext4 filesystem details
sudo xfs_info /dev/sda1            # XFS filesystem details
```

### LVM (Logical Volume Manager) — Enterprise Standard

```bash
# LVM layers: Physical Volume → Volume Group → Logical Volume

# View LVM configuration
sudo pvs                          # Physical volumes
sudo vgs                          # Volume groups
sudo lvs                          # Logical volumes
sudo pvdisplay                    # Detailed PV info
sudo vgdisplay                    # Detailed VG info
sudo lvdisplay                    # Detailed LV info

# Extend a logical volume (most common SRE task!)
# Scenario: /var is full, you have free space in the VG
sudo vgs                          # Check VFree column
sudo lvextend -L +10G /dev/vg_name/lv_var    # Add 10GB
sudo lvextend -l +100%FREE /dev/vg_name/lv_var  # Use all free space
sudo resize2fs /dev/vg_name/lv_var            # Resize ext4 filesystem
sudo xfs_growfs /var                           # Resize XFS filesystem
```

**Lab: [lab-1.3-disk-emergency.sh](labs/lab-1.3-disk-emergency.sh)**

---

## 1.4 Process Management and Investigation

### Understanding Processes

```bash
# ──────────────────────────────────────
# Viewing Processes
# ──────────────────────────────────────
ps aux                            # All processes (BSD syntax)
ps -ef                            # All processes (System V syntax)
ps aux --sort=-%mem | head -20    # Top 20 by memory
ps aux --sort=-%cpu | head -20    # Top 20 by CPU
ps -eo pid,ppid,user,%cpu,%mem,stat,start,time,comm --sort=-%cpu | head -20

# Process tree
pstree                            # Full process tree
pstree -p                         # With PIDs
pstree -p <PID>                   # Tree for a specific process

# ──────────────────────────────────────
# top and htop — Real-Time Monitoring
# ──────────────────────────────────────
top                               # Real-time process viewer
# Inside top:
#   P = sort by CPU       M = sort by memory
#   k = kill process      r = renice process
#   c = show command       1 = per-CPU view
#   f = select fields      q = quit

htop                              # Better top (install: apt install htop)
# Inside htop:
#   F5 = tree view        F6 = sort by column
#   F9 = kill             F2 = setup

# ──────────────────────────────────────
# Process Information Deep Dive
# ──────────────────────────────────────
# /proc/<PID>/ is a goldmine
cat /proc/<PID>/status            # Process status details
cat /proc/<PID>/cmdline | tr '\0' ' '  # Full command line
ls -la /proc/<PID>/fd             # Open file descriptors
cat /proc/<PID>/limits            # Resource limits
cat /proc/<PID>/environ | tr '\0' '\n'  # Environment variables
ls -la /proc/<PID>/cwd            # Current working directory
ls -la /proc/<PID>/exe            # Executable path

# ──────────────────────────────────────
# Signals — Communicating with Processes
# ──────────────────────────────────────
kill -l                           # List all signals
kill <PID>                        # Send SIGTERM (graceful shutdown)
kill -9 <PID>                     # Send SIGKILL (force kill — last resort!)
kill -HUP <PID>                   # Send SIGHUP (reload config)
kill -USR1 <PID>                  # Send SIGUSR1 (app-specific)

killall nginx                     # Kill all processes by name
pkill -f "python server.py"       # Kill by command pattern

# ──────────────────────────────────────
# Finding Processes
# ──────────────────────────────────────
pgrep -a nginx                    # Find PIDs by name
pidof nginx                       # Get PID of a running program
lsof -p <PID>                     # All files opened by a process
lsof -i :80                       # What's using port 80?
lsof -u username                  # Files opened by a user
fuser -v /var/log/syslog          # Who's using this file?
```

**Lab: [lab-1.4-process-investigation.sh](labs/lab-1.4-process-investigation.sh)**

---

## 1.5 Networking Fundamentals for SRE

### Essential Network Commands

```bash
# ──────────────────────────────────────
# Interface and IP Configuration
# ──────────────────────────────────────
ip addr show                      # All interfaces and IPs (replaces ifconfig)
ip addr show eth0                 # Specific interface
ip link show                      # Interface state (UP/DOWN)
ip route show                     # Routing table
ip route get 8.8.8.8              # How traffic reaches a destination
ip neigh show                     # ARP table (MAC addresses)

# ──────────────────────────────────────
# Connectivity Testing
# ──────────────────────────────────────
ping -c 4 8.8.8.8                 # Basic connectivity (ICMP)
ping -c 4 google.com              # Test DNS + connectivity
traceroute 8.8.8.8                # Path to destination
traceroute -n 8.8.8.8             # Without DNS resolution (faster)
mtr google.com                    # Continuous traceroute (install: apt install mtr)

# ──────────────────────────────────────
# DNS Troubleshooting
# ──────────────────────────────────────
dig google.com                    # DNS query (detailed)
dig +short google.com             # DNS query (just the answer)
dig @8.8.8.8 google.com           # Query a specific DNS server
dig google.com MX                 # Query for mail records
dig -x 8.8.8.8                    # Reverse DNS lookup
nslookup google.com               # Alternative DNS query
host google.com                   # Simple DNS lookup
cat /etc/resolv.conf              # DNS resolver configuration
resolvectl status                 # systemd-resolved status

# ──────────────────────────────────────
# Port and Connection Analysis
# ──────────────────────────────────────
ss -tlnp                          # TCP listening ports + PIDs
ss -ulnp                          # UDP listening ports + PIDs
ss -tnp                           # Established TCP connections
ss -s                             # Socket statistics summary
ss -tn state established          # Only established connections
ss -tn state time-wait            # Connections in TIME_WAIT
ss -tn '( dport = :443 )'        # Connections to port 443

# Count connections by state
ss -tn | awk '{print $1}' | sort | uniq -c | sort -rn

# ──────────────────────────────────────
# Testing Ports
# ──────────────────────────────────────
nc -zv hostname 80                # Test if port is open
nc -zv hostname 20-100            # Port range scan
curl -v http://hostname:80        # HTTP test with details
curl -k https://hostname          # HTTPS ignoring cert errors
curl -w "\n%{http_code} %{time_total}s\n" http://hostname  # Response code + time

# ──────────────────────────────────────
# Firewall (iptables/nftables)
# ──────────────────────────────────────
sudo iptables -L -n -v            # List all rules
sudo iptables -L INPUT -n --line-numbers  # Input chain with line numbers
sudo nft list ruleset             # nftables rules
sudo ufw status verbose           # UFW status (Ubuntu)
```

**Lab: [lab-1.5-network-troubleshooting.sh](labs/lab-1.5-network-troubleshooting.sh)**

---

## 1.6 User and Permission Management

```bash
# ──────────────────────────────────────
# User Management
# ──────────────────────────────────────
id                                 # Current user info
id username                        # Specific user info
whoami                             # Current username
w                                  # Who's logged in and what they're doing
last                               # Login history
last -f /var/log/btmp              # Failed login attempts
lastlog                            # Last login for all users

# User database files
cat /etc/passwd                    # User accounts
cat /etc/shadow                    # Password hashes (root only)
cat /etc/group                     # Group definitions

# ──────────────────────────────────────
# Permission Troubleshooting
# ──────────────────────────────────────
ls -la /path/to/file               # File permissions
stat /path/to/file                 # Detailed file info
getfacl /path/to/file              # Extended ACLs
namei -l /path/to/file             # Permissions along entire path!

# Permission format: rwxrwxrwx = user|group|other
# r=4, w=2, x=1
chmod 755 file                     # rwxr-xr-x
chmod u+x file                     # Add execute for owner
chown user:group file              # Change ownership
chown -R user:group /dir/          # Recursive ownership change

# Special permissions
# SUID (4): runs as file owner    — e.g., /usr/bin/passwd
# SGID (2): runs as file group    — e.g., shared directories
# Sticky bit (1): only owner can delete — e.g., /tmp
find / -perm -4000 -type f 2>/dev/null  # Find SUID files
find / -perm -2000 -type f 2>/dev/null  # Find SGID files
```

**Lab: [lab-1.6-permission-debugging.sh](labs/lab-1.6-permission-debugging.sh)**
