# ravenhill.cl

Personal website of Ignacio Slater Muñoz: external lecturer at Universidad de Chile, researcher in
metaheuristic optimization, and Kotlin/Scala developer. It is a minimalist static profile that
links to academic and teaching projects.

## 📄 Overview

A single hand-written HTML page styled with [Pico.css](https://picocss.com), with no build step.
[`index.html`](index.html) is the only source of truth for site content (biography, publications,
courses, contact links); this README does not repeat it.

The [modernization roadmap](https://gitlab.com/r8vnhill/ravenhill-cl/-/work_items) (epics E0–E5) is
tracked on GitLab.

## 🛠️ Structure

```text
ravenhill-cl/
├── index.html          # Site content (served)
├── robots.txt          # Crawler rules (served)
├── wrangler.toml       # Cloudflare Worker static-asset configuration
├── .assetsignore       # Files excluded from the Cloudflare upload
├── docs/
│   └── deployment.md   # Deploy source, asset contract, credentials, rollback
├── tests/
│   ├── Deployment.Contract.psd1  # Declared deployment contract (single source of truth)
│   ├── Deployment.Helpers.psm1   # Test helpers (probing, file classification, hashing)
│   └── Deployment.Tests.ps1      # Pester suites: local contract and live site
├── dprint.json         # Formatter configuration
├── cspell.json         # Spell-checker project dictionary
├── CONTRIBUTING.md     # Contribution policy
├── LICENSE             # BSD 2-Clause License
├── .gitignore          # Git ignore rules
├── .gitattributes      # Line-ending normalization
└── .vscode/            # Optional editor settings (gitignored)
```

## 🚀 Deployment

**Every push to `main` on GitHub (`origin`) is a production release**, built by Cloudflare Workers
Builds. Only the files in `PublicAssets` (`index.html`, `robots.txt`) are meant to be served; every
other file must be listed in [`.assetsignore`](.assetsignore). Read
[docs/deployment.md](docs/deployment.md) before changing deployment, adding root files, or pushing.

Checks require PowerShell 7 and Pester 5.5 or later:

```powershell
Invoke-Pester ./tests -ExcludeTagFilter Production  # offline contract; run before committing
git fetch origin; Invoke-Pester ./tests -TagFilter Production  # live site; after each deploy
```

## 🔗 Contact

- GitHub: [@r8vnhill](https://github.com/r8vnhill)
- GitLab: [@r8vnhill](https://gitlab.com/r8vnhill)

## 📄 License

Licensed under the [BSD 2-Clause License](LICENSE).
