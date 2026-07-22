# Security

This repo is public. Everything below follows from that one fact.

## Setup

```sh
brew install gitleaks   # the scanner; not vendored, not auto-installed
make setup              # points core.hooksPath at .githooks/ and verifies it fires
```

`make setup` is safe to re-run and verifies more than it configures — it feeds a
known-detectable fake key to the real hook and asserts the hook objects. Run it
whenever you are unsure whether your clone is protected.

Git deliberately runs nothing on clone, so this cannot install itself. One
command is the floor.

## If a secret is committed: rotate first

**Rotate the credential before you touch git history.** Not after. Not
"while I'm rewriting the branch". First.

Rewriting history feels like undoing the leak, but it isn't, and the time spent
on it is time the live credential stays valid:

- The old commit stays reachable in your local repo, in every clone, and in any
  fork, until each is garbage-collected — which you do not control.
- If it was pushed to GitHub, the commit remains fetchable by SHA even after a
  force-push, and stays in the API and in forks' networks.
- Push events feed public firehoses that credential-scrapers watch. Assume the
  value was harvested within seconds, not minutes.

So: history rewriting is cleanup. Rotation is the fix. Do the fix first, then
clean up at your leisure — and treat the credential as compromised regardless.

## A key in an iOS binary is not secret

Anyone can unzip an `.ipa` and read its strings, `Info.plist`, and embedded
`.xcconfig` values. Gitignoring a file keeps it out of *this repo*; it does
nothing about the app you ship.

This means there is no such thing as a client-side API secret. If a task seems
to need one, the answer is architectural — a backend that holds the credential
and exposes only the narrow operation the app needs. Raise it; don't work
around it.

`Local.xcconfig` is gitignored for a different reason: a `DEVELOPMENT_TEAM` ID
is personal identity, not a secret, and doesn't belong in a public project.

## False positives

If gitleaks flags a value that genuinely isn't a credential — a test fixture, a
sample of the right *shape* — annotate that line:

```
STRIPE_KEY = "sk_live_EXAMPLE_NOT_A_REAL_KEY" # gitleaks:allow
```

Scope the exemption to the single line. Never disable a rule repo-wide, and
never add a path to an ignore list to get a commit through.

Keep example credentials obviously fake, as above. A realistic-looking sample
still trips GitHub's push protection, which does not honour `gitleaks:allow` —
and that block lands on whoever next pushes, not on whoever wrote the line.
