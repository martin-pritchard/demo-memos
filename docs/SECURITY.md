# Security — handling secrets

> Copied in by the sdlc plugin's `/setup`. This copy belongs to the repo:
> adapt it, and add stack-specific traps as they become real.

**No secrets in this repo. That sentence is the actual control; everything
below is a net for when it fails.**

## The rule

No credentials, API keys, tokens, certificates, or `.env` files — not in
source, not in config, not in tests, not in a commit you plan to amend away
later. If the repo is public, pushed means public.

## The client-app trap, which `.gitignore` does not solve

Any key shipped inside a client artifact is extractable — an iOS `.ipa`, an
Android `.apk`, a JS bundle. Gitignoring the file that holds the key keeps it
out of *git* while still shipping it to every user. If the app needs a
third-party API key, the key belongs on a server that proxies the call; the
client holds a user token, not the vendor key. That is an architecture
decision — raise it, don't reach for a gitignored config file.

## Layers in place

1. **GitHub push protection** — server-side, on by default for public repos;
   verify in Settings → Code security. It matches known vendor patterns
   only; an opaque random key sails through it.
2. **gitleaks pre-commit hook** (`.githooks/pre-commit`) — covers that gap,
   and is the only layer that fires *before* a secret leaves your machine.
   Fails closed: no gitleaks, no commit (`brew install gitleaks`). New
   clones run `git config core.hooksPath .githooks` once (`/setup` does).

No CI secret-scanning, deliberately: on a public repo CI runs *after* the
push — by then the secret is already public. Detection theatre.

## If a secret lands anyway

**Rotate first. Always.** Treat any committed secret as compromised: forks
keep the commit reachable forever, and bots scrape the public firehose in
seconds. Rewriting history addresses the embarrassment, not the exposure.

1. Revoke/rotate the credential at the provider — the leak is now worthless.
2. Remove it from the code and commit the fix.
3. Optionally scrub history (`git filter-repo`) and ask GitHub Support to
   purge cached views. This is tidying, not remediation.
4. Note why the layers missed it (an opaque key is the known gap).

## Placeholders and the tracked-file gotcha

Sample values must be obviously fake (`sk_test_EXAMPLE_NOT_A_REAL_KEY`);
silence a false positive with a trailing `gitleaks:allow` comment, not by
weakening the ruleset. Commit `.env.example`, never `.env`. And remember
`.gitignore` does not untrack an already-tracked file — `git rm --cached`
untracks it, and by then: rotate.
