# Deployment: source, asset contract, and recovery

How <https://ravenhill.cl/> is produced from this repository, what it may serve, and how to release
and recover it. Established in [E0.1][e01]; it is the baseline for [E0.2][e02], [E2.1][e21], and
[E5.2][e52].

**Audience:** maintainers and AI agents changing deployment, adding files to the repository root,
or pushing to `main`.

**Executable form:** [`tests/Deployment.Tests.ps1`](../tests/Deployment.Tests.ps1), driven by
[`tests/Deployment.Contract.psd1`](../tests/Deployment.Contract.psd1). If this document and the
tests disagree, the tests are authoritative; fix this document in the same commit.

## Rules for maintainers and agents

1. **A push to GitHub `main` is a production release.** That includes documentation-only commits.
   Get explicit approval before pushing `main`, and never force-push it.
2. **The site serves the repository root.** Any new file is public unless it is excluded:
   - For a non-site file, add it to [`.assetsignore`](../.assetsignore).
   - For a site file, add it to `PublicAssets` in `Deployment.Contract.psd1`.
3. **Run the offline suite before every commit:**
   `Invoke-Pester ./tests -ExcludeTagFilter Production`.
4. **Never commit secrets.** With the root-directory upload, a committed secret is published unless
   it is excluded.
5. **Keep remotes in sync.** After pushing GitHub, push the same `main` to GitLab.
6. **Change contract values in one place:** `Deployment.Contract.psd1`. The test file and
   `.assetsignore` must not duplicate them, beyond the exclusion list itself.

## Topology

```text
local working copy
  │  git push github main
  ▼
GitHub r8vnhill/ravenhill-cl, branch main      authoritative deploy source
  │  push webhook (Cloudflare GitHub App)
  ▼
Cloudflare Workers Builds                      shallow detached checkout; wrangler deploy
  │
  ▼
Worker "ravenhill-cl" (static assets only)
  ├── https://ravenhill.cl/
  └── https://www.ravenhill.cl/                same content, no canonical redirect

GitLab r8vnhill/ravenhill-cl                   issue tracker; manually pushed remote,
                                               not a mirror, no deploy rights
```

## Findings (audit of 2026-11-09)

- **Deploy mechanism:** Cloudflare Workers Builds. The served `/.git/logs/HEAD` showed
  `buildbot <buildbot@cloudchamber.(none)>  checkout: moving from master to 7608a56…`.
- **Deploy source:** GitHub `r8vnhill/ravenhill-cl`, branch `main`. The served `/.git/FETCH_HEAD`
  read `7608a56… of https://github.com/r8vnhill/ravenhill-cl`, and `git ls-remote origin` agreed.
- **Release commit at audit:** `7608a561223073963c28b0e83fb2bbc484e1583d`, from the served
  `/.git/HEAD`.
- **Content match:** the served `/` was byte-identical to `index.html` at `7608a56` (blob
  `3b8c40a`).
- **GitLab state:** `main` was at `f9cf2ad`, two commits behind GitHub. It is not configured as a
  mirror (`mirror` and `import_url` are empty in the API).
- **Worker configuration** ([`wrangler.toml`](../wrangler.toml)): `name = "ravenhill-cl"`,
  `[assets] directory = "."`, no Worker script, `compatibility_date = 2025-06-26`.
- **Edge HTML rewrite:** Cloudflare Web Analytics injects a `static.cloudflareinsights.com` beacon
  `<script>` before `</body>` for browser-like clients; curl receives the untouched file. The
  setting lives on the Cloudflare zone, not in this repository. Content checks must strip the
  beacon first (`ConvertTo-SourceHtml`).
- **Credentials:** none in the repository. The served `.git/config` has a token-free HTTPS remote.

### Public routes

| Request                     | Response                                                 |
| --------------------------- | -------------------------------------------------------- |
| `GET /`                     | `200 text/html`, `public, max-age=0, must-revalidate`    |
| `GET /robots.txt`           | `200 text/plain`                                         |
| `GET /index.html`           | `307` to `/` (default assets HTML handling)              |
| `GET http://ravenhill.cl/`  | `301` to `https://ravenhill.cl/`                         |
| `GET https://www.…/`        | `200`, same page; no canonical redirect (E2.1)           |
| Unknown path                | `404`; no single-page-app fallback, no custom 404 page   |

### Repository-root exposure (security finding)

Because `[assets] directory = "."`, Workers Builds uploads the whole checkout except
`.assetsignore` entries. The original file excluded only `.vscode`, `*.log`, and `*.swp`, so the
audit found these served with `200`:

- **Git metadata:** `/.git/HEAD`, `config`, `index`, `logs/HEAD`, `FETCH_HEAD`, `shallow`,
  `description`, and by implication the object pack.
- **Repository files:** `/README.md`, `/CONTRIBUTING.md`, `/LICENSE`, `/wrangler.toml`,
  `/dprint.json`, `/.gitignore`, `/.gitattributes`.

The impact is low, because the repository is public and nothing exposed contains credentials.
Still, it leaks build details, contradicts the intended site surface, and would publish any future
secret.

**Hotfix (E0.1):** `.assetsignore` now excludes `.git` and every non-site file explicitly, which
leaves only `index.html` and `robots.txt`. The permanent fix is E2.1/E5.2: upload only a build
output directory (`dist/`).

## Tests

The suite in `tests/` has three files:

- **`Deployment.Contract.psd1`** is the declared contract: defaults, Worker name, assets directory,
  `PublicAssets`, and the git metadata paths to probe.
- **`Deployment.Helpers.psm1`** holds the logic:
  - It loads the contract with environment overrides.
  - It classifies files the way the build checkout would see them: tracked files plus untracked,
    non-gitignored files.
  - It probes URLs without following redirects.
  - It computes git blob hashes for content identity.
- **`Deployment.Tests.ps1`** has the declarative suites:
  - **Asset contract (local)** runs offline and is safe anywhere. It checks the `wrangler.toml`
    values, that `.assetsignore` includes `.git` and has no negations, and that every repository
    file is either public or excluded.
  - **Production** (tag `Production`) makes network requests. It checks that the served `/`
    (beacon removed) hashes to `<SourceRef>:index.html`, the routes table above, and that every
    non-public repository file and `.git` path returns 404.

| Variable               | Default                | Purpose                                |
| ---------------------- | ---------------------- | -------------------------------------- |
| `RAVENHILL_BASE_URL`   | `https://ravenhill.cl` | Site to probe; use for preview URLs    |
| `RAVENHILL_SOURCE_REF` | `github/main`          | Git ref expected to be in production   |

The Production suite describes what is **deployed**. Run `git fetch github` first, and expect the
exposure tests to fail between a local fix and its deploy.

**Extending the suite:**

- **New observed route:** add an entry to `$routes` in `BeforeDiscovery`.
- **New git metadata path:** add it to `GitMetadataPaths`.
- **New served file:** add it to `PublicAssets`.

Non-public repository files need no test changes; they are derived from the file list.

## Publishing

1. Commit to `main`, and make sure the offline suite passes.
2. `git push github main` (GitHub). Workers Builds deploys the new commit.
3. `git push origin main` (keeps GitLab in sync).
4. When the build finishes: `git fetch github; Invoke-Pester ./tests -TagFilter Production`.

## Credentials boundary

- **Cloudflare** holds deploy authority: the Workers Builds connection to GitHub, through the
  Cloudflare GitHub App, and the build API token. Neither is stored in this repository.
- **GitHub** holds write access to the deploy branch. Anyone who can push `main` can publish.
- **GitLab** has no deploy credentials or CI. E5.2 plans to move deploy authority here.

## Verifying the release commit

`/.git/HEAD` is no longer served, so traceability comes from content identity: the Production
suite compares the served page, beacon removed, with `git rev-parse <SourceRef>:index.html`. To
check a specific commit:

```powershell
$env:RAVENHILL_SOURCE_REF = '<sha>'; Invoke-Pester ./tests -TagFilter Production
```

The Cloudflare dashboard (Worker → Deployments) also shows the commit SHA for each build.

## Rollback and recovery

- **Fastest:** in the Cloudflare dashboard, go to Workers & Pages → `ravenhill-cl` → Deployments,
  pick a previous version, and roll back. `npx wrangler rollback <version-id>` does the same with
  an authenticated wrangler. Production changes immediately; `main` does not.
- **Durable:** `git revert <bad-sha>` and `git push github main`. Do it after an instant rollback,
  so the next push does not reintroduce the problem.
- **Worker lost:** from the repository root, run `npx wrangler deploy` with an authenticated
  wrangler. Then reattach the `ravenhill.cl` and `www.ravenhill.cl` custom domains, and reconnect
  Workers Builds to the GitHub repository.

## To confirm in the Cloudflare dashboard

These were inferred from public behavior, not read from the account. Tick each item when it is
confirmed, and record any difference.

- [ ] The Workers Builds production branch is `main`.
- [ ] The build command is empty; the deploy command is the default `npx wrangler deploy`.
- [ ] Whether non-production branch builds (`wrangler versions upload` previews) are enabled.
- [ ] `ravenhill.cl` and `www.ravenhill.cl` are attached as custom domains, not routes.
- [ ] Web Analytics (RUM) automatic injection is enabled on the zone, which explains the beacon.
- [ ] The scope of the build API token.

## Hand-offs

- **E0.2:** extend `tests/` for baseline checks; the public routes table is the observed baseline.
- **E2.1:**
  - Build to `dist/` and update `AssetsDirectory` in the contract deliberately.
  - Decide on a canonical host (`www` to apex) and a custom 404 page.
  - Strip the edge beacon in any HTML snapshot test.
- **E5.2:**
  - Moving deploys to GitLab CI requires disabling Workers Builds, so there are never two
    publishers.
  - Run the Production suite as the post-deploy smoke test (`RAVENHILL_BASE_URL` for previews).
  - Consider an explicit release identifier in place of content hashing.

[e01]: https://gitlab.com/r8vnhill/ravenhill-cl/-/work_items/7
[e02]: https://gitlab.com/r8vnhill/ravenhill-cl/-/work_items/8
[e21]: https://gitlab.com/r8vnhill/ravenhill-cl/-/work_items/11
[e52]: https://gitlab.com/r8vnhill/ravenhill-cl/-/work_items/21
