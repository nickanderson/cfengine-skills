# Real agents for Mission Portal cases (design, not built)

`lib/mp-clone-hosts.sh` gives a case many hosts that look real, but cf-hub
never collects them: freshness, lastseen and agent status are whatever `tick`
writes. Cases about *why a host looks wrong* (mp-01, mp-05, future ones) need
the hub's own collection path, so their hosts should run real `cf-agent`.

## Shape

10-20 podman containers on the workstation, each a real CFEngine client
bootstrapped to the 3.27.1 hub:

- Images: `debian:12` and `rockylinux:9` with the agent packages already in
  `vagrant/3.27/3.27.1/packages/` (`PACKAGES_x86_64_linux_debian_12`,
  `agent_rhel9_x86_64`). systemd as PID 1 (`podman run --systemd=always`) so
  cf-execd / cf-serverd / cf-monitord run as on a real host, and a scenario
  can stop them the way an operator would.
- Keys persisted per container in a named volume, so a host keeps its
  identity across restarts; recreating the volume is how a scenario makes a
  host key collision or a "reinstalled" host.
- ~60 MB RAM each; 20 hosts fit easily (workstation: 20 cores, 62 GB).

## Networking: the one hard part

cf-hub collects by connecting to the client's port 5308 at the address it
last saw the client connect from. So each container needs its own address on
192.168.56.0/24 that the hub can reach and that its own outgoing connections
come from:

- **macvlan on `vboxnet0`** (192.168.56.1/24 on the workstation): containers
  get 192.168.56.100-.119 as real L2 addresses. First thing to verify, since
  VirtualBox's host-only switch has to pass the extra MACs to the hub VM.
- Not port publishing: `-p 192.168.56.10x:5308:5308` makes the hub reach the
  container, but the container's own connections to the hub are NATed to
  192.168.56.1, so every container shows up in lastseen at one address and
  collection goes to the wrong place.
- Fallback if macvlan fails: call-collect (the client opens the collection
  connection). Real, but a different path from the vagrant hosts'.

## Scenario controller

`lib/mp-agents.sh up | down | apply <scenario> | reset`. A scenario is a list
of hosts and what is done to each, applied through the same levers a real
operator has, never by editing cfdb:

| Scenario            | Lever                                             | Health category          |
|---------------------|---------------------------------------------------|--------------------------|
| agent stopped       | `systemctl stop cf-execd` in the container        | agentNotRunRecently      |
| unreachable         | `podman pause`, or drop 5308 in its netns         | notRecentlyCollected     |
| policy failing      | augments / host-specific data that breaks a bundle| lastAgentRunUnsuccessful |
| deleted, reporting  | API delete while it keeps running                 | deletedHostsReport       |
| same name           | two containers with one hostname                  | hostsUsingSameName       |
| same identity       | two containers sharing one key volume             | hostsUsingSameIdentity   |
| clock skew          | `faketime` around cf-agent, or a skewed netns     | agentNotRunRecently      |
| never collected     | bootstrap, then block the hub's inbound 5308      | hostsNeverCollected      |

`apply` is idempotent and ends by waiting for the hub to show the expected
category (via `/api/health-diagnostic`), so a case's preflight can call it and
know the fixture is live rather than assume it. That replaces most of
`mp-setup-hub.sh` and removes the host001/host002/host003 VM fixtures, which
cost a VM each and drift (host003's Guest Additions truncating /vagrant).

## Order

1. Prove macvlan on vboxnet0 with one container: bootstrap, one collection
   seen in `__hosts.lastreporttimestamp`. Everything else depends on it.
2. Controller with two scenarios (agent stopped, deleted-still-reporting),
   and an mp-05 variant graded against them next to the VM-based mp-05.
3. The rest of the table; retire the VM fixtures once scores agree.
