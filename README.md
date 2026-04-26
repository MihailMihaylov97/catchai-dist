# catchai-dist

**Internal distribution repo for the catchai scanner.** Wheels live in
GitHub Releases; this repo also serves the public `install.sh`.

This repo contains **no scanner source code**. Source lives in the
private `catchai` repo. Wheels here are produced by `catchai`'s
`release.yml` GitHub Actions workflow and pushed via deploy key.

---

## Access tiers

| Group | Access |
|---|---|
| Internal team | Direct repo access. `gh release download` works. |
| Beta enterprise customers | No repo access. Wheels reachable via `dl.catchai.io` with their license key. |
| Public free-tier users | No repo access. Wheels reachable via `dl.catchai.io` (no key required, rate-limited). |

The repo itself stays **private**. End users never see this URL — they
only see `install.catchai.io` (which serves `install.sh` from this
repo's `main` branch via CDN) and `dl.catchai.io` (a download proxy
that fronts GitHub Releases on this repo).

---

## What's here

```
catchai-dist/
├── README.md                          this file
├── install.sh                         public installer — served via install.catchai.io
├── checksums/
│   └── v0.5.0.txt                     SHA-256 manifest per release tag
├── docs/
│   └── INTERNAL_RELEASE_GUIDE.md      cut-a-release runbook for ops
└── .github/ISSUE_TEMPLATE/
    └── bad-release.md                 internal template for "v0.5.1 wheel is broken"
```

The wheels themselves live in **GitHub Releases on this repo** —
attached to each version tag, not committed. Layout per release:

```
v0.5.0/
├── catchai-0.5.0-cp311-abi3-macosx_11_0_universal2.whl
├── catchai-0.5.0-cp311-abi3-linux_x86_64.whl
├── catchai-0.5.0-cp311-abi3-linux_aarch64.whl
└── checksums.txt
```

No `.tar.gz`, no source. Just compiled wheels + checksums.

---

## How releases land here

1. Engineer cuts a tag in the **`catchai`** source repo (private).
2. `catchai`'s `release.yml` workflow builds three wheels (macOS arm64,
   Linux x86_64, Linux aarch64) in parallel.
3. The final job uses the `CATCHAI_DIST_DEPLOY_KEY` secret (an SSH
   deploy key with write access to *this* repo only) to:
   - Create a GitHub Release in `catchai-dist` named `v<version>`
   - Attach all three wheels + the checksums file
   - Commit a per-release checksums manifest under `checksums/`
4. `dl.catchai.io` (CDN-fronted download proxy) picks up the new release
   on next request — no deploy step here.

**This repo's CI does not build anything.** All build work happens in
`catchai`. This separation is what keeps source-access and wheel-access
as distinct authorization concerns.

---

## How to debug a broken release

See [`docs/INTERNAL_RELEASE_GUIDE.md`](./docs/INTERNAL_RELEASE_GUIDE.md).

If a customer reports a broken wheel, file an issue using the
`bad-release.md` template — it captures the version, platform, and the
error so we can track it without losing context.

---

## Security

The `CATCHAI_DIST_DEPLOY_KEY` is the only credential with write access
to this repo. It lives only in `catchai`'s GitHub Actions secrets and
should be rotated annually. Compromise of this key would let an
attacker upload a malicious wheel to a Release — treat it accordingly.

The Ed25519 license-signing private key used to sign customer license
JWTs lives separately, also in `catchai`'s secrets. See
`catchai/docs/dev/CATCHAI_Repos.md §6` for the full custody model.
