# Level 1: Linux Foundations — Summary & Key Lessons

> Completed: February/March 2026
> All 6 labs completed step-by-step with manual commands.

---

## Lab 1.1 — Boot Process Analysis

### What We Did
- Ran `systemd-analyze`, `systemd-analyze blame`, `systemd-analyze critical-chain`
- Read boot errors with `journalctl -b -p err`
- Identified failed services with `systemctl --failed`

### Findings on This Machine
- Total boot time: **4.185s** (904ms kernel + 3.280s userspace)
- Machine is a **VM** (identified by `dev-vda.device`)
- **docker.service** (1.456s) is the critical path bottleneck
- 0 failed services, 0 boot errors

### Key Lessons
- **Critical-chain ≠ all services.** systemd starts many services in parallel. The critical-chain is the longest *sequential* dependency chain — the path that determined total boot time.
- **`After=` controls ordering only.** `Requires=` controls dependency. A service can be `After=` something without failing if that something fails.
- **Journal permissions matter.** Without `adm` or `systemd-journal` group membership, `journalctl` silently shows incomplete logs. Always use `sudo journalctl` or fix group membership.

---

## Lab 1.2 — Systemd Service Management

### What We Did
- Manually created a systemd unit file from scratch
- Started, enabled, broke, diagnosed, and fixed a service
- Used `systemctl status`, `journalctl -u`, `systemctl show -p ExecStart`

### Real Bugs Hit During This Lab
| Bug | Symptom | Root Cause |
|---|---|---|
| Missing closing quote in script | Service failed immediately | `echo "$(date): Server is running >> log` — redirect inside string |
| Lost execute bit after `tee` | `status=203/EXEC` | `tee` recreates files without preserving permissions |
| Blank line before shebang | `status=203/EXEC` | Kernel reads first 2 bytes for `#!` — blank line breaks detection |
| Wrong binary path | `status=203/EXEC` crash loop | Intentional break — unit file pointed to `doesnt-exist.sh` |

### The Diagnostic Workflow
```
1. systemctl status <service>       → what state? what error code?
2. journalctl -u <service>          → what has it been doing?
3. systemctl show -p ExecStart      → what is systemd actually running?
4. fix root cause
5. systemctl daemon-reload          → only if unit file changed
6. systemctl restart <service>
7. systemctl status <service>       → confirm active (running)
```

### Key Lessons
- **`daemon-reload` is required after every unit file edit.** systemd caches unit files in memory. Without it, your changes are ignored.
- **`status=203/EXEC` has multiple causes.** Missing execute bit, blank line before shebang, wrong path — all produce the same error code. Only investigation reveals which.
- **`Restart=on-failure` without `StartLimitBurst` loops forever.** A broken service with no restart limit floods your logs and consumes CPU. Always set `StartLimitBurst`.
- **`[Install]` is only read by `enable/disable`.** It has zero effect at runtime. `WantedBy=multi-user.target` creates a symlink — that's all enable does physically.

---

## Lab 1.3 — Disk Space Emergency

### What We Did
- Created a 100MB loop device filesystem
- Filled it to capacity, observed write failures
- Used `du -sh * | sort -rh` to find large files
- Exhausted inodes with 25,000+ tiny files

### Key Lessons
> **A disk can be "full" in two completely different ways.**

```
df -h   →  are we out of bytes?    (space exhaustion)
df -i   →  are we out of inodes?   (inode exhaustion)
```

- **`No space left on device`** is the error you'll see in app logs, database logs, and service crashes when a disk fills. Know it immediately.
- **Failed writes leave partial files behind.** A write that hits the disk limit creates a partial file that still consumes space. Always check for these during cleanup.
- **Inode count is fixed at `mkfs` time.** You cannot add inodes without reformatting. The only fixes are: delete files, extend the volume, or migrate to XFS/btrfs.
- **Common inode exhausters:** email servers (Maildir), PHP session files, thumbnail caches, build artifact directories — anything creating many small files.

---

## Lab 1.4 — Process Investigation

### What We Did
- Spawned CPU hog processes (computing π to 10,000 decimal places in a loop)
- Spawned a memory hog (Python allocating 1MB every 0.5s)
- Investigated with `ps aux`, `/proc/<PID>/status`, `pgrep`
- Killed offenders with `pkill -f`

### Reading `ps aux`
```
USER    PID   %CPU  %MEM   VSZ    RSS   STAT  COMMAND
root    377    1.0   1.4  208676  123028  S    systemd-journald

VSZ  = virtual memory claimed (may not all be in RAM)
RSS  = resident set size — actual physical RAM in use RIGHT NOW
STAT = process state
```

### Process States
| State | Meaning | SRE concern |
|---|---|---|
| `R` | Running | Normal for active processes |
| `S` | Sleeping (interruptible) | Normal |
| `D` | Uninterruptible sleep | Danger — waiting for hung I/O, **cannot be killed** |
| `Z` | Zombie | Parent hasn't cleaned up — usually harmless but worth investigating |
| `T` | Stopped | Paused with Ctrl+Z |

### Key Lessons
- **`D` state processes cannot be killed, even with `kill -9`.** They're waiting for I/O (usually a hung disk or NFS mount). The fix is resolving the I/O issue, not killing the process.
- **`pkill -f` kills by command pattern, `kill` kills by PID.** When a runaway process has spawned multiple instances, `pkill -f` eliminates all at once.
- **`/proc/<PID>/` is the deepest truth about a process.** Status, open files, environment variables, command line, resource limits — all available without any external tool.
- **VmRSS ≈ VmSize means the process is actively using all its claimed memory** — signature of a memory hog. A healthy process claims much more than it uses.

---

## Lab 1.5 — Network Troubleshooting

### What We Did
- Started a Python HTTP server, verified it with `ss -tlnp`
- Tested connectivity with `curl`
- Simulated an outage by killing the server
- Diagnosed using a layer-by-layer approach
- Restored the service

### The Layer-by-Layer Diagnostic Approach
```
When "service isn't reachable", check in this order:

1. ss -tlnp | grep <port>           → is anything listening?
2. pgrep -a <process>               → is the process running?
3. sudo iptables -L INPUT -n        → is a firewall blocking it?
4. dig +short google.com            → is DNS working?
5. ping $(ip route | grep default | awk '{print $3}')  → is the gateway reachable?
```

### `ss -tlnp` Flags Decoded
```
t = TCP only
l = Listening ports only
n = Numeric (don't resolve names)
p = show Process owner
```

### Key Lessons
- **Always check `ss -tlnp` before anything else.** If nothing is listening on the port, the problem is the process — don't investigate the network.
- **`0.0.0.0:8080` vs `127.0.0.1:8080` matters.** `0.0.0.0` accepts connections from all interfaces. `127.0.0.1` is localhost only — a service bound to localhost is unreachable from outside the machine.
- **`lsof -i :<port>` shows the owning process with username.** Critical for knowing if a service is running as root vs a service account.
- **Find the problem layer before acting.** Restarting a service when the gateway is down wastes time. Layer-by-layer diagnosis tells you who to call.

---

## Lab 1.6 — Permission Debugging

### What We Did
- Created files with restrictive permissions (`600`, `700`)
- Attempted access as `labuser` — observed `Permission denied`
- Used `namei -l` to trace permissions along the full path
- Fixed with `chown -R` and `chmod`
- Verified with `namei -l` again

### Permission Number Cheatsheet
```
r=4  w=2  x=1    →  add them per group: owner | group | others

600  rw-------   owner read/write only         (private keys, secrets)
640  rw-r-----   owner rw, group read           (app config)
644  rw-r--r--   owner rw, world read           (public web files)
700  rwx------   owner full, no one else        (private directories)
750  rwxr-x---   owner full, group read+enter   (app directories)
755  rwxr-xr-x   owner full, world read+enter   (public directories)
```

### Key Lessons
- **A restrictive parent directory blocks everything inside it.** A file with `644` permissions is unreachable if its parent directory is `700` and owned by someone else. Always check the full path.
- **`namei -l /path/to/file` is the fastest permission debugger.** It shows owner, group, and permissions for every component of the path — pinpoints the blocking point immediately.
- **`chown -R` changes ownership recursively.** Always follow with explicit `chmod` on each level — don't assume a single chmod covers all cases.
- **`sudo -u <user> <command>` simulates access as that user.** Use this to verify permissions are correct before deploying, rather than waiting for the app to fail.

---

## Critical Patterns Carrying Into Level 2

### 1. The Universal Diagnostic Loop
```
Observe  →  Gather data  →  Form hypothesis  →  Test  →  Fix  →  Verify
```
Every lab used this. In Kubernetes the tools change but the loop is identical.

### 2. Logs Are the First Truth
`journalctl` in Linux → `kubectl logs` in Kubernetes. Always read logs before touching configuration.

### 3. Two Ways Everything Can Be "Full"
- Disk: bytes (`df -h`) vs inodes (`df -i`)
- Kubernetes equivalent: resource requests vs actual limits, pod capacity vs node capacity

### 4. Permissions Block Silently
`Permission denied` in Linux → RBAC/ServiceAccount errors in Kubernetes. The same principle: trace the full access path, not just the final resource.

### 5. Process State Determines Action
- `D` state (uninterruptible) in Linux → `Terminating` pod stuck in Kubernetes (finalizers, PVCs)
- Both require resolving the underlying I/O/dependency, not force-killing

### 6. Layer-by-Layer Network Diagnosis
Linux: interface → port → process → firewall → DNS → gateway
Kubernetes: pod → service → endpoint → network policy → DNS → ingress

---

*Level 2: Kubernetes Foundations — next.*
