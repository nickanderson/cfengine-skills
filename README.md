# CFEngine Skills for Claude Code

Skills that teach [Claude Code](https://code.claude.com/) how to work with
CFEngine policy and CFEngine Enterprise.

## Skills

| Skill | Purpose |
|-------|---------|
| `cfengine-policy` | Write, review, and debug CFEngine `.cf` files, augments, and cfbs projects |
| `mission-portal` | Script the Mission Portal REST API: hosts, SQL reports, custom-SQL alerts, Health diagnostics |

## Install

Clone the repo, then link the skill into your Claude Code skills directory:

```bash
git clone https://github.com/nickanderson/cfengine-skills.git \
    ~/src/cfengine-skills
ln -s ~/src/cfengine-skills/cfengine-policy ~/.claude/skills/cfengine-policy
ln -s ~/src/cfengine-skills/mission-portal ~/.claude/skills/mission-portal
```

The skills appear as `/cfengine-policy` and `/mission-portal` in Claude Code.

Claude Code looks for `~/.claude/skills/<name>/SKILL.md` and does not search
further down, so cloning the repo *into* `~/.claude/skills/` leaves the skill
one level too deep to be found. Link the skill directory itself, as above.

## What it does

On first use the skill:

1. Clones the [CFEngine documentation](https://github.com/cfengine/documentation)
   repo, matching the branch to your installed `cf-agent` version
2. Checks for missing tools (`cf-agent`, `cf-promises`, `cfengine` CLI) and
   prints install guidance
3. Loads a concise policy language reference into context

The documentation checkout is cached at `~/.local/share/cfengine/docs/` and
updated weekly. Override with `CFENGINE_DOCS_DIR`.

## Connecting `mission-portal` to a hub

The skill never handles your password. It calls the hub through
`scripts/mp-api.sh`, which reads credentials from a netrc file that `curl`
consumes directly, so the password stays out of the conversation, command
lines, and output. Set it up once:

```bash
mkdir -p ~/.config/cfengine
echo 'url=https://hub.example.com' > ~/.config/cfengine/mission-portal.conf
echo 'machine hub.example.com login <your-login> password <password>' >> ~/.netrc
chmod 600 ~/.netrc
```

For a hub with a self-signed certificate, save the hub's certificate and add
`cacert=/path/to/hub.pem` to the config file; the skill prints the commands
when it first sees an untrusted certificate. The login is your own: the agent
can do whatever your role allows, and the audit log records its actions under
your name. It asks before any change to the hub, and `mp-api.sh` refuses changes
unless called with `--write`, which the skill does not pre-approve -- so
Claude Code asks you again before it runs. Treat that as a speed bump; your
role is the boundary. The REST API does not enforce
2FA.

| Variable | Config key | Effect |
|---|---|---|
| `MP_URL` | `url=` | Hub URL (required) |
| `MP_NETRC` | `netrc=` | Netrc file (default `~/.netrc`) |
| `MP_CACERT` | `cacert=` | Hub certificate to trust |
| `MP_INSECURE` | `insecure=` | `1` skips certificate checks (lab hubs only) |
| `MP_CONFIG` | | Config file (default `~/.config/cfengine/mission-portal.conf`) |

## Staying up to date

The skill also checks whether its own checkout has fallen behind this repo, and
tells Claude to ask you before doing anything about it. It never updates itself:
the update is a `git pull` in your checkout, so it is yours to approve.

It is built to stay out of your way.

- Silent when there is nothing to decide. It prints only when the skill itself
  has changed upstream.
- Commits that do not touch the skill -- eval results, tests, this README --
  are not worth interrupting you for, and do not trigger a notice.
- It fetches at most weekly, and re-raises a notice you have already seen at
  most weekly. A new upstream version re-notifies immediately.
- Uncommitted local edits to the skill are reported, never discarded. If you
  have edited the skill *and* upstream has moved, it says so and declines to
  hand over a pull command.
- A failed fetch, an unreachable remote, or a copied-in (non-git) install all
  exit quietly. A skill that fails to render because the network is down is
  worse than a skill that is a week stale.

| Variable | Effect |
|----------|--------|
| `CFENGINE_SKILL_UPDATE_DISABLE=1` | Turn the check off entirely |
| `CFENGINE_SKILL_UPDATE_INTERVAL_DAYS` | Days between fetches (default 7) |
| `CFENGINE_SKILL_UPDATE_NOTICE_DAYS` | Days before repeating a notice (default 7) |

## Tests

```bash
tests/test-ensure-docs.sh          # documentation checkout behaviour
tests/test-check-skill-update.sh   # update-check behaviour
tests/test-mp-api.sh               # Mission Portal wrapper, incl. no password leaks
```

All are hermetic -- local fixture repos and a fake hub stand in for the
remotes, so they need no network and no CFEngine install.

## Prerequisites

- [Claude Code](https://code.claude.com/)
- `cf-remote` -- optional but recommended. Tooling to provision install and bootstrap CFEngine. (https://github.com/cfengine/cf-remote) (`uv tool install cf-remote`).
- CFEngine CLI -- optional but recommended. Tooling to help work with CFEngine and policy. (https://github.com/cfengine/cfengine-cli) (`uv tool install cfengine`).
- CFEngine (`cf-agent`) -- optional but recommended. Install from
  [cfengine.com/downloads](https://cfengine.com/downloads) or via `cf-remote` or `cfengine` CLI

## License

Apache 2.0
