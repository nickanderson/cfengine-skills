# cfengine-policy skill eval

A persistent A/B harness for `cfengine-policy/SKILL.md`. Every run asks the same
prompt twice — once with the skill exposed, once without — then grades both
answers with the installed CFEngine binaries rather than with another model.
Results are stamped with the skill's git hash so score movement can be attributed
to a specific skill revision.

## Run it

```bash
./eval/run-eval.sh                            # all cases, sonnet, both sides
./eval/run-eval.sh --case 01-motd --runs 3    # three samples per side
./eval/run-eval.sh --functional               # also prove augments actually override
./eval/run-eval.sh --report-only              # rebuild report from existing results
./eval/run-eval.sh --help
```

`run-eval.sh` needs `claude` and `python3` on PATH, plus `podman` and the eval
image. Override the image with `--image REF` or `$CFEVAL_IMAGE`; pass
`--no-container` to fall back to the host's `cf-promises`/`cf-agent`, which is
also what happens automatically if the image is missing.
Spawning the sub-`claude` with `--dangerously-skip-permissions` may require a
`Bash(./eval/run-eval.sh:*)` allow rule in your settings; `--safe-perms` swaps it
for `--permission-mode acceptEdits --permission-prompts none`, at the cost of the
generated agent no longer being able to run `cf-promises` introspection itself.

## Isolation

Each side runs in a throwaway jail:

- `mktemp -d` working directory, discarded after the artifacts are copied out
- a fresh `CLAUDE_CONFIG_DIR` holding only a copy of `.credentials.json`, so the
  global `CLAUDE.md`, pre-installed skills (including `cfengine-policy-reference`
  from ce-toolkit), plugins and project settings cannot leak into either side
- `--strict-mcp-config` (and `--no-session-persistence` under `--driver print`)
- no `CLAUDE*` variables from the shell that started the harness: started
  from inside Claude Code, they make every nested `claude` a child of that
  session (it wrote no transcript, and shared its messaging socket)

### Driver: a console session, not `claude -p`

By default (`--driver console`) each invocation is what a user at a terminal
does: `lib/console-claude.sh` starts interactive `claude` in a detached
`screen` session, waits for the prompt box, pastes the case prompt (bracketed
paste, so its newlines stay newlines), presses Enter, waits for the turn to
end (a Stop hook in the jail's settings records it), types `/cost`, and
`/exit`s. First-run screens (theme, folder trust, the bypass-permissions
warning) are pre-answered in the jail's config, since a returning user never
sees them. The run keeps `console.log` (everything the terminal showed),
`screen-final.txt` and `transcript.jsonl`, and the driver writes `raw.json`
in the `-p` shape so grading is unchanged: the answer is the last assistant
text, turns are API responses in the transcript, cost and API time are what
`/cost` showed. `--driver print` runs `claude -p` as before; the driver is
recorded in `run-info.json` and each run's `meta.json`.

The console session runs in a container, not on the workstation:
`container/Containerfile` builds `localhost/cfeval-console:<hash>` on the
grader's CFEngine image (so the model validates with the CFEngine the grader
uses), adds cfbs, the cfengine CLI, git and jq, and leaves out vagrant,
podman and psql, which on the host led around the "through the API" cases
straight into the hub. The host's `claude` binary is mounted read-only, the
jail at its own path, the docs checkout read-only; the session's environment
is only the case's `env` and the skill's config. `--session-image none`
runs it on the workstation instead. Compare effort only
between runs of the same driver: the two count turns differently.

Both sides get the same base system prompt. The **only** difference is that
`with-skill` installs the skill and is told to use it. Nothing in either prompt
mentions augments, `isvariable`, or `def.json` beyond what the case prompt says.

## How the skill reaches the model

The skill is **installed**, not handed over as a file: `cfengine-policy/` is
copied to `<jail>/config/skills/cfengine-policy/` and `scripts/` alongside it,
so Claude Code loads it the way it loads any skill.

This matters more than it sounds, and the eval got it wrong at first. The
original version passed `--add-dir <repo>/cfengine-policy` and told the model to
read `SKILL.md`. That grades a file no user is ever given: a SKILL.md contains
` ```! ` blocks that the *harness* executes at load time, splicing their stdout
into the skill text. Read as a plain file, those blocks never run, so the model
never receives the documentation paths, the detected `cf-agent` version, or the
missing-tool warnings that a real load provides.

Two things that are easy to get wrong here, both found by testing rather than
by reading:

- **Claude Code does not search below `skills/<name>/SKILL.md`.** Copying the
  repo in wholesale leaves the skill one level too deep and silently undiscovered.
  The install must be flat. (The project README had this bug too.)
- **`--disable-slash-commands` also disables skills.** The eval used to pass it
  for isolation. With the skill installed but that flag set, the with-skill side
  was quietly just a second baseline -- it scored *below* the unaided run before
  this was caught. A fresh config dir has no custom commands to guard against,
  so the flag is simply gone.

`CFENGINE_SKILL_UPDATE_DISABLE=1` is set in the jail, so the skill's own
update notice cannot vary the rendered text with how stale the checkout is.

Runs recorded before this change are marked `skill add-dir` in the timeline and
banded as their own ruler regime. They are not worse numbers on the same
measurement -- they measured a different artifact.

## Where the CFEngine binaries run

`cf-promises` and `cf-agent` run **inside a container**, not on the host. Three
reasons, in order of how much they bite:

1. **`cf-agent` reports the host's real `sys.*` values.** The functional check
   shells out to `--show-evaluated-vars`, so an unfiltered result file ends up
   holding `sys.bindir` (your home directory) and `sys.uqhost` (your hostname).
   In the container those are `/var/cfengine/bin` and a fixed `cfeval`.
2. **Generated policy is untrusted.** `cf-agent -Kn` makes no changes, but
   function calls like `execresult()` still evaluate. That belongs in a
   container, and validation runs with `--network=none`.
3. **Scores stop being host-dependent.** The image pins the CFEngine version, so
   a run on another machine is comparable. `run-info.json` records the image.

The `sys.*` allowlist is dumped from that same image, with networking left on --
with `--network=none` the agent reports no interfaces, and `sys.interfaces` or
`sys.hardware_mac` in generated policy would look hallucinated. Six further
variables are real but absent from a plain Community container (`policy_hub`,
`enterprise_version` and friends); they are listed in `lib/extra-sys-vars.txt`
and unioned in, so the allowlist matches a stock host exactly.

## Grading

Nothing is graded by an LLM. Every check is mechanical:

| Check | Weight | How |
|---|---|---|
| Policy passes `cf-promises` standalone | 25 | `cf-promises -c -f`; 60% credit if it only passes once `stdlib.cf` is included |
| No hallucinated `sys.*` variables | 10 | every `sys.X` reference compared against `cf-agent --show-evaluated-vars=sys` on this host |
| 3 augments tunables present | 15 | distinct `isvariable("...def.X")` references |
| `ifelse(isvariable(...))` instrumentation | 20 | each tunable wrapped in `ifelse()`, the pattern the skill teaches |
| Tunables namespaced consistently | 10 | SKILL.md accepts either `default:def.` or bare `def.`, so both earn full credit; only an inconsistent mix is marked down |
| `def.json` augments example provided | 10 | a written or fenced JSON file with a `vars` or `variables` object |
| `def.json` keys match policy tunables | 10 | fully-qualified JSON keys ∩ fully-qualified tunable names |

Two details that took some finding, and that are easy to get wrong if this harness
is ever rewritten:

- **`cf-promises -b` silently disables the undefined body/bundle check.** A policy
  that only defines library bundles would otherwise fail on `Bundle 'main' ... is
  not a defined bundle`, so the harness writes a synthetic `body common control`
  entry file that `inputs` the policy instead of passing `-b`.
- **The stdlib retry prepends `body file control` to every `.cf` in the staging
  copy**, because `inputs` is per-file -- a wrapper on the entry point does not
  reach the files it includes.
- **`def.json` has two accepted shapes.** `vars` maps a bare name to a value;
  `variables` maps a name -- optionally fully qualified, e.g. `default:motd.path`
  -- to `{value, comment, tags}`. Both were verified on this host to drive the
  override, so both count. Keys are compared fully qualified: a bare key lands in
  `default:def`, so it matches a `default:def.x` tunable, while an explicitly
  qualified key only matches that exact variable.

## Known limitation: the rubric grades conformance, not function

The tunable checks (55 of the 100 points) look for the specific pattern the skill
teaches: a `def.` indirection read through `ifelse(isvariable("default:def.x"))`.
A policy can be fully augments-configurable without it -- declaring
`"default:motd.banner"` directly in `variables` and guarding the policy's own
promise with `unless => isvariable("banner")` also works, and was confirmed
working on this host. Such an answer scores 0 on those checks despite being
correct.

So the headline delta measures *adherence to the skill's guidance*, which is what
a skill eval should measure -- but it is not a measure of whether the un-skilled
answer was broken. Read the `--functional` result, which dry-runs the policy, as
the ground truth on whether augments actually take effect -- it is reported as
a headline tile beside the score for exactly this reason, so a
working-but-nonconformant answer is never mistaken for a broken one. A tile
reading `n/a NOT TESTED` means no `def.` tunables were found to inject, not
that the policy failed. Broadening the tunable
detection to count the `unless => isvariable()` idiom would turn this into a
functional-correctness eval instead; that is a deliberate open choice, not an
oversight.

`--functional` goes further: it dry-runs the policy (`cf-agent -Kn`) with a
synthetic `def.json` full of sentinel values and checks the sentinels actually
reach the variables. That proves the tunables are wired up, not just shaped right.
It is opt-in because it evaluates model-generated policy.

## Mission Portal cases: the live hub is the oracle

Cases prefixed `mp-` measure the `mission-portal` skill. There is no
`cf-promises` for a REST call, so these are graded against a real CFEngine
Enterprise hub instead of a container. Each case names its skill and grader in
`case.json` (`"skill": "mission-portal"`, `"grader": "mission-portal"`), and a
run measures one skill at a time:

```bash
export MP_URL=https://192.168.56.2 MP_USER=admin MP_PASSWORD=...
./eval/run-eval.sh --skill mission-portal --variant no-skill   # baseline, no skill needed
./eval/run-eval.sh --case mp-01-health
```

The model gets the same `MP_*` variables, and the grader runs the script it
wrote against the hub. The expected answer is **re-derived from the hub's own
API at grading time**, never stored in the case, so a hub with different hosts
still grades correctly. Stored answers would go stale the moment a host
reports.

Two things keep a live oracle honest:

- **Preflight.** A healthy hub makes an empty answer correct. Each case lists
  the state it needs (`expect.require_categories`), and `bin/grade_mp.py
  --preflight` refuses to start the run unless the hub is in that state.
  `lib/mp-setup-hub.sh` puts it there; for `mp-01-health` that means
  stopping `cf-execd` on one client and deleting another while it keeps
  reporting, then waiting ~10 minutes for the first to be flagged.
- **Credentials never reach the results.** `secret_env` names the variables to
  redact; the harness passes their values to `scrub.py`, which replaces them in
  every artifact. Models echo the password into scripts and replies.

**Diagnosis, not retrieval.** `mp-05-diagnose` lists five, numbered, each
written as a user would write it -- what they see and their theory, not a
Health category -- and asks for the cause from a fixed list plus the evidence:
hostkeys, timestamps with a UTC offset, the role and the single class that
hides a host. Two of the writers'
theories are wrong (the hub *is* collecting; the hub is *not* at fault), one
answer needs the class inside an exclude expression, and one timestamp has a
decoy: `/api/hosts/deleted` keeps the last report from before deletion, while
the host is still trying now. Timestamps the hub keeps moving are accepted if
recent, not future. It uses the `mp-01` fixtures plus user `alice` with role
`web_team`, both from `lib/mp-setup-hub.sh`.

**Cases that change the hub.** `mp-06-remove-host` asks for a script that
removes a host for good, so every run destroys its own target. A case can name
a `pre_run` script (relative to `eval/`, with arguments) that the harness runs
before each model invocation; mp-06 uses `lib/mp-synthetic-hosts.sh create`
to make `decomm01.example.com` and a decoy, `lab-decomm01.example.com`, with
Mission Portal's data generator. The grader recreates them again, runs the
model's script, and judges only the resulting state -- the hub's status codes
are the traps: `DELETE /api/host/:key` returns 202 for any key, existing or
not; permanent deletion of a live host is a 404; and the path from older docs,
`/api/host/delete-permanently/...`, is taken as a regular delete of a host
called "delete-permanently", 202 again. host002 must survive in the deleted
list. The grader needs `MP_VAGRANT_DIR`; the harness strips it from the
model's environment. Controls: a correct script 100, a substring match with a
regular delete 50, the old docs path 75.

mp-06 is also the one case that can wreck the hub: its agents hold a login
that deletes hosts, and on 2026-09-23 a no-skill agent deleted every real host
while testing its script. So it is marked `"exclusive"` -- run-eval takes a
lock per hub, shared by read-only runs and exclusive for mp-06, which waits for
other hub runs and holds new ones off -- and its `post_run` is
`lib/mp-recover-hub.sh`. That checks the real hosts after every invocation
(about two seconds when nothing is wrong) and brings back any that are gone:
undelete, re-bootstrap the client, collect, and if the record is still empty,
purge it and bootstrap again. It keeps host002 deleted-but-reporting and
restarts its `cf-serverd` if its reports go stale. Run it by hand when a
preflight fails after anything that deletes hosts.

**Stay under the hub's license.** A free Enterprise hub covers 25 clients.
Past that, `cf-hub` stops collecting from every host, and the Health fixtures
quietly turn into "Unreachable hosts" -- the preflight caught exactly this
after 1120 generator hosts were added for `mp-03-all-hosts`. That case needs
a hub licensed past 1122 hosts (the eval hub has 2000, from nova's
`make_license_file` against the hub's `ppkeys/localhost.pub`, installed as
`/var/cfengine/license.dat`).

**Synthetic fleets.** mp-03's `pre_run` is `lib/mp-clone-hosts.sh create
1118`: host001's real reporting rows cloned into 1118 hosts, each with its own
hostkey, names, IP, MACs, UUID and matching classes, and fresh enough to stay
off the Health page. Its `post_run` removes them after grading, so they never
reach another case's fixtures; `mp-setup-hub.sh` removes any an interrupted
run left. Mission Portal's own data generator is kept only for mp-06, whose
two hosts are never inspected: its values (MD5 product names, CFEngine 3.14
classes on a 3.27 hub) give a fleet away as fake.

Scores are only comparable across runs against a hub of the same version,
since the health categories and API shapes move between releases.
`run-info.json` does not record the hub version yet -- read it from
`GET /api` when comparing.

## Layout

```
eval/
  run-eval.sh              driver
  bin/analyze.py           extract + validate + check + score one run
  bin/aggregate.py         summary.json + append history.jsonl
  bin/report.py            self-contained HTML report for one run
  bin/compare.py           cross-model comparison from history.jsonl
  bin/grade_mp.py          grade a Mission Portal case against the live hub
  bin/refresh-sys-vars.sh  dump this host's real sys.* variables
  cases/<id>/prompt.txt    the prompt
  cases/<id>/case.json     rubric weights and expectations
  lib/mp-setup-hub.sh      put the eval hub into the state the mp-* cases grade
  lib/extra-sys-vars.txt   real sys vars a plain container does not define
  cache/sys-vars.txt       regenerated at the start of every run
  results/<timestamp>/     run-info.json, summary.json, SKILL.md.snapshot,
                           report.html, plus response/workdir/result.json per run
  results/history.jsonl    one row per run × case × side — the progression record
  results/latest-report.html   symlink to the newest run's report (generated)
  results/compare.html         every model side by side (generated)
  archive/                     superseded runs, kept but not published
```

## Reading the output

`run-eval.sh` writes two views, and they answer different questions:

- **`results/latest-report.html`** — a symlink to the *newest invocation's* report.
  One model, aggregated over its `--runs` repetitions (the tiles show the mean with
  the min–max spread beside it), plus that model's score progression across every
  run it has ever had. It does **not** span models.
- **`results/compare.html`** — every model that has run each case, side by side.
  One dumbbell per model: the orange dot is no-skill, the blue dot is with-skill,
  and the connector length is the skill delta. The faint rule behind each dot is
  the run range, so a 5-run spread is visible instead of hidden inside a mean.

### Effort: turns, cost, time

Beside the score, every run records what the answer cost to produce: agent
turns, USD, and wall time, from the Claude CLI's own result. They are aggregated
per variant (mean with min-max, in `summary.json` and `history.jsonl`), shown
as a second row of tiles with an **effort delta**, and as a `Turns` column
(`no-skill -> with-skill`) in `compare.html`.

They are deliberately **not part of the score**. Folding them in would re-base
every case, and would let a fast-but-partly-wrong answer tie a slow-but-right
one. Read them together: the score says whether the skill makes the answer
right, the effort says whether it makes it cheap. On a case the unaided model
can solve by exploring -- `mp-01-health`, where Sonnet reached 96.7 without the
skill but took 19 to 90 turns ($0.37 to $2.62) doing it -- effort is the only
place the skill can show up.

Turns and cost vary a lot between runs of the same prompt (the range above is
three runs), so compare means over `--runs 3` or more, not single runs.

Regenerate the comparison by hand at any time — it reads only `history.jsonl`, so
it needs no model calls:

```bash
python3 eval/bin/compare.py --history eval/results/history.jsonl \
        --results-dir eval/results --out eval/results/compare.html
```

Pass `--case ID` (repeatable) to narrow it; with no `--case` it renders every case
found in the history.

## What is committed

The framework, the cases, and the per-run evidence (`result.json`, `response.md`,
the generated `workdir/`, `cmd.sh`, `system-prompt.txt`, `SKILL.md.snapshot`) plus
`history.jsonl`. Deliberately **not** committed, see `eval/.gitignore`:

- `raw.json` -- redundant with `response.md` + `result.json`, and carries session ids
- `stderr.log` -- empty in every run so far
- `report.html` / `compare.html` -- generated; rebuild them with no model calls via
  `./eval/run-eval.sh --report-only`
- `cache/` -- host-specific, regenerated at the start of every run

Artifacts are redacted by `bin/scrub.py`, which runs over each run's output
directory *after* analysis -- so `cf-promises` validates the bytes the model
actually wrote, not a rewritten copy. `$HOME` becomes `~`, the hostname becomes
`<host>`, and `run-info.json` records a platform string rather than a hostname.
This matters more than it sounds -- the functional check shells out to
`cf-agent --show-evaluated-vars`, whose output carries `sys.bindir`, `sys.uqhost`
and friends, so an unfiltered dump would put the machine's identity in every
result file.

Email addresses need a narrower rule than the other two. Claude Code injects a
`userEmail` block into every run's context, and the model will volunteer that
address as a plausible contact value in generated policy -- this is observed, not
theoretical. But a blanket "replace every address" rule also destroys the
fictional examples the skill teaches with (`help@acme.com`, `ops@globex.com`),
corrupting the artifact it was meant to protect. So `scrub.py` keeps an address
that appears in the model's own inputs -- `SKILL.md` and the case prompt, passed
as `--allow-from` -- or that sits at a documentation domain, and replaces
anything else with `admin@example.com`, naming each replacement on stderr.

**Artifact caveat for the 2026-09-21 eval runs.** Those three runs were scrubbed
once by an earlier, blanket version of that rule, which rewrote example addresses
as well as the one real one. Recorded scores and functional results are
unaffected -- they were computed before the scrub, and the rubric grades
structure and keys, never string values. The skill snapshots were restored from
the byte-identical `SKILL.md` (verified against the `skill_sha256` in every
`meta.json`). One artifact is no longer self-consistent: in
`20260921-181725-sonnet/01-motd/with-skill/run04`, a tunable's in-policy default
and its `def.json` override now read the same string, so *re-grading that saved
run* would report it as not overridden. The originally recorded result for it
stands.

## Attributing a score to a skill revision

`run-info.json` stamps the skill's commit, sha256 and dirty flag, and each run
re-hashes `SKILL.md` after the model returns. If the skill is edited while an
eval run is in flight, that run's `meta.json` gets `skill_changed_during_run: true`
and the run prints a warning -- its score belongs to neither revision and should
be discarded. This is not hypothetical: it happened during the first eval run, and
three opus runs silently graded against a skill that had changed underneath them.

Weights live in `case.json`, so scores are only comparable while the weights hold.
Changing them re-bases the ruler; archive the old runs rather than charting across
the change.

## Adding a case

```bash
mkdir -p eval/cases/02-mything
echo "Write a CFEngine policy that ..." > eval/cases/02-mything/prompt.txt
cp eval/cases/01-motd/case.json eval/cases/02-mything/case.json   # edit id/title/weights
./eval/run-eval.sh --case 02-mything
```

Weights live in `case.json`, so a case can zero out a check that does not apply to
it. Scores stay comparable across runs as long as the weights do not change — if
you change them, the progression chart is comparing different rulers.
