# Internal release guide

How to cut a `catchai` release if you're not the lead engineer.

## Prerequisites

- Push access to `MihailMihaylov97/catchai` (the source repo)
- `gh` CLI logged in
- Local clone of `catchai` with `dev` and `main` branches up to date

## Cut a release

From inside the `catchai` source repo:

```bash
# 1. Make sure dev is clean and CI is green
git checkout dev
git pull
gh run list --branch dev --limit 1   # last run should be 'completed: success'

# 2. Bump the version in pyproject.toml
$EDITOR pyproject.toml                # find: version = "0.5.0" → bump

# 3. Run the release driver
./scripts/release.sh 0.5.1

# What it does:
#   - Verifies clean tree
#   - Runs full local test suite
#   - Builds one wheel locally as smoke test
#   - Tags v0.5.1 on dev → push → fast-forward main
#   - Triggers .github/workflows/release.yml on the new tag
#   - Polls until all 3 wheels land in catchai-dist Releases
#   - Mirrors install.sh to catchai-dist/main
#   - Verifies install.catchai.io serves the new install.sh
```

Total wall-clock: ~6 minutes from invocation to wheels available.

## If the release fails midway

| Failure point | What to do |
|---|---|
| Local smoke build fails | Fix the build, abort the release. No tag was pushed yet. |
| Tag pushed, build fails on CI | Delete the remote tag, fix, retry. Wheels never made it to `catchai-dist`. |
| Wheels uploaded to wrong release name | Manually delete the bogus release in `catchai-dist`, retry. |
| Only 2 of 3 wheels uploaded | Re-run the failing job in `catchai`'s release.yml. The release.yml is idempotent — it overwrites existing assets. |
| `install.sh` mirror failed | Re-run the `mirror-install-sh` step manually: see "Manual mirror" below. |

## Customer-reported "wheel is broken"

1. File an issue using the **bad-release.md** template
2. Confirm the SHA-256 in `catchai-dist/checksums/v<version>.txt`
   matches what the customer downloaded:
   ```bash
   shasum -a 256 ~/Downloads/catchai-*.whl
   ```
3. If checksums match: the build is wrong, not the transit. Rebuild:
   ```bash
   gh workflow run release.yml --repo MihailMihaylov97/catchai \
     --field version=0.5.1 --field force_rebuild=true
   ```
4. If checksums don't match: the customer's download was corrupted or
   tampered. Tell them to re-run the curl installer.

## Manual mirror of install.sh

If the automated mirror step in `release.yml` failed:

```bash
# from the catchai source repo
gh repo clone MihailMihaylov97/catchai-dist /tmp/catchai-dist
cp dist/install.sh /tmp/catchai-dist/install.sh
cd /tmp/catchai-dist
git add install.sh
git commit -m "mirror install.sh from catchai v0.5.1"
git push
```

The `install.catchai.io` CDN cache TTL is 60 seconds; new installs
pick up the change immediately.

## Rotating the deploy key

The `CATCHAI_DIST_DEPLOY_KEY` should be rotated annually:

1. Generate a new SSH keypair:
   ```bash
   ssh-keygen -t ed25519 -f /tmp/catchai-dist-deploy -N ""
   ```
2. Add the **public** half to `catchai-dist` as a deploy key with
   write access (Settings → Deploy keys → Add).
3. Add the **private** half to `catchai`'s Actions secrets as
   `CATCHAI_DIST_DEPLOY_KEY` (Settings → Secrets and variables →
   Actions → New repository secret).
4. Cut a smoke-test release (`v0.0.0-rc-rotation-test`) to verify
   the new key works.
5. Delete the old deploy key from `catchai-dist`.
6. Delete the old secret from `catchai`.

## Who has access to what

| Resource | Who | How |
|---|---|---|
| `catchai` source repo | Internal eng team | GitHub repo collaborator |
| `catchai-dist` source (this repo) | Internal eng + ops | GitHub repo collaborator |
| `catchai-dist` Releases (download wheels) | Eng + ops + license-key holders | `gh release download` for first two; `dl.catchai.io` for license holders |
| `CATCHAI_DIST_DEPLOY_KEY` | No one — it lives in CI | Rotate via procedure above |
| Ed25519 license signing key | Lead eng + KMS | See `catchai/docs/dev/CATCHAI_Repos.md §6` |

## Open work

- The `dl.catchai.io` proxy isn't built yet (deferred to v0.6 per
  `CATCHAI_Repos.md §3`). Until then, the `catchai-dist` repo serves
  free-tier wheels via direct GitHub Releases.
- `auth.catchai.io` (license issuance + heartbeat) doesn't exist.
  License keys are generated manually until then.
