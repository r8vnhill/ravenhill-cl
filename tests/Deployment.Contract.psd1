# Single source of truth for the ravenhill.cl deployment contract (E0.1).
#
# Read by tests/Deployment.Tests.ps1 through Get-DeploymentConfig (Deployment.Helpers.psm1). Do not
# copy these values into other files. When the contract changes, update this file, .assetsignore,
# and docs/deployment.md in the same commit.
@{
  # Defaults for the live-site suite. Override with RAVENHILL_BASE_URL / RAVENHILL_SOURCE_REF.
  BaseUrl         = 'https://ravenhill.cl'
  SourceRef       = 'origin/main'

  # Expected wrangler.toml values. AssetsDirectory changes to a build output (dist/) in E2.1.
  WorkerName      = 'ravenhill-cl'
  AssetsDirectory = '.'

  # Repository files that are intentionally served. Every other file in the checkout must be listed
  # in .assetsignore, or the local contract test fails.
  PublicAssets    = @('index.html', 'robots.txt')

  # Git metadata that Workers Builds leaves in its checkout. Not visible to `git ls-files`, so the
  # live-site suite probes these paths explicitly in addition to every non-public repository file.
  GitMetadataPaths = @(
    '.git/HEAD'
    '.git/config'
    '.git/index'
    '.git/logs/HEAD'
    '.git/FETCH_HEAD'
    '.git/shallow'
    '.git/description'
  )
}
