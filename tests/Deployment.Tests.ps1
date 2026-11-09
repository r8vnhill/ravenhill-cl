#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

<#
.SYNOPSIS
  Characterizes the ravenhill.cl deployment source and Cloudflare static-asset contract (E0.1).

.DESCRIPTION
  Two suites, both driven by tests/Deployment.Contract.psd1 (the single source of truth):

  - "Asset contract (local)" runs offline against the working tree. It fails when a file in the
    checkout would be uploaded to Cloudflare without being an intended public asset, or when
    wrangler.toml drifts from the documented contract.
  - "Production" (tag: Production) probes the live site. It checks that the deployed page matches
    the authoritative source ref, that public routes behave as documented, and that no non-site
    file or git metadata is served.

  The Production suite reports what is deployed, not what is in the working tree: run
  `git fetch origin` first, and expect exposure failures until a fix has been pushed and built.

.EXAMPLE
  Invoke-Pester ./tests -ExcludeTagFilter Production   # offline, run before every commit

.EXAMPLE
  Invoke-Pester ./tests -TagFilter Production           # live site, run after each deploy

.EXAMPLE
  $env:RAVENHILL_SOURCE_REF = '<sha>'; Invoke-Pester ./tests -TagFilter Production

.NOTES
  Environment overrides: RAVENHILL_BASE_URL (site to probe) and RAVENHILL_SOURCE_REF (git ref
  expected in production). See docs/deployment.md for the context behind each assertion.
#>

# Pester shares variables between BeforeDiscovery/BeforeAll and It blocks through its own scoping,
# which PSScriptAnalyzer cannot follow; every flagged variable is used by a -ForEach or an It block.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
  'PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester block scoping'
)]
param()

BeforeDiscovery {
  Import-Module (Join-Path $PSScriptRoot 'Deployment.Helpers.psm1') -Force
  $config = Get-DeploymentConfig
  $apex = $config.BaseUrl
  $published = { param($path) $path -in $config.PublicAssets }

  $repositoryFiles = Get-RepositoryFile |
    ForEach-Object { @{ Path = $_; IsPublic = & $published $_ } }

  $privatePaths = Get-PrivateUrlPath -Config $config | ForEach-Object { @{ Path = $_ } }

  # Observed public behavior (2026-11-09). Header/Pattern are optional response-header checks.
  $routes = @(
    @{ Name = '/ is served as HTML'; Url = "$apex/"; Status = 200
      Header = 'Content-Type'; Pattern = '^text/html' }
    @{ Name = '/robots.txt is served as plain text'; Url = "$apex/robots.txt"; Status = 200
      Header = 'Content-Type'; Pattern = '^text/plain' }
    @{ Name = '/index.html redirects to /'; Url = "$apex/index.html"; Status = 301, 302, 307, 308
      Header = 'Location'; Pattern = '^/$' }
    @{ Name = 'HTTP redirects to HTTPS'; Url = ($apex -replace '^https:', 'http:') + '/'
      Status = 301, 308; Header = 'Location'; Pattern = '^https://' }
    @{ Name = 'unknown paths return 404 (no SPA fallback)'; Url = "$apex/__e01-missing__"
      Status = 404 }
    @{ Name = 'www serves the page without a canonical redirect (see E2.1)'
      Url = ($apex -replace '^https://', 'https://www.') + '/'; Status = 200 }
  )
}

BeforeAll {
  Import-Module (Join-Path $PSScriptRoot 'Deployment.Helpers.psm1') -Force
  $config = Get-DeploymentConfig
}

Describe 'Asset contract (local)' {
  Context 'wrangler.toml' {
    BeforeAll {
      $wrangler = Get-Content -Path (Join-Path $config.RepoRoot 'wrangler.toml') -Raw
    }

    It 'deploys the Worker named in the contract' {
      $wrangler | Should -Match "(?m)^name\s*=\s*`"$([regex]::Escape($config.WorkerName))`""
    }

    It 'serves assets from the contract directory (changes deliberately in E2.1)' {
      $directory = [regex]::Escape($config.AssetsDirectory)
      $wrangler | Should -Match "(?ms)^\[assets\].*?^directory\s*=\s*`"$directory`""
    }

    It 'declares no Worker script (assets-only deployment)' {
      $wrangler | Should -Not -Match '(?m)^main\s*='
    }
  }

  Context '.assetsignore' {
    BeforeAll {
      $patterns = Get-AssetIgnorePattern
      $ignored = Get-RepositoryFile -AssetIgnored
    }

    It 'excludes the .git directory left by the build checkout' {
      $patterns | Should -Contain '.git'
    }

    It 'uses no negation patterns, so exclusions stay explicit' {
      $patterns | Where-Object { $_.StartsWith('!') } | Should -BeNullOrEmpty
    }

    It '<Path> is uploaded only if it is a public asset' -ForEach $repositoryFiles {
      $reason = if ($IsPublic) { 'it is listed in PublicAssets' }
      else { 'it is not a site asset; add it to .assetsignore or to PublicAssets' }
      ($Path -notin $ignored) | Should -Be $IsPublic -Because $reason
    }
  }
}

Describe 'Production' -Tag 'Production' {
  Context 'Source-to-production mapping' {
    BeforeAll {
      $homePage = Invoke-Probe -Url "$($config.BaseUrl)/"
      $html = Get-ResponseText -Response $homePage
    }

    It 'serves index.html from the source ref, ignoring the edge analytics beacon' {
      $homePage.StatusCode | Should -Be 200
      $expected = Get-SourceBlobHash -Ref $config.SourceRef -Path 'index.html'
      Get-GitBlobHash -Text (ConvertTo-SourceHtml -Html $html) |
        Should -Be $expected -Because "production should match $($config.SourceRef) (git fetch?)"
    }

    It 'has the Cloudflare Web Analytics beacon injected at the edge (not in source)' {
      Test-EdgeBeacon -Html $html | Should -BeTrue
    }
  }

  Context 'Public routes' {
    It '<Name>' -ForEach $routes {
      $response = Invoke-Probe -Url $Url
      $response.StatusCode | Should -BeIn $Status
      if ($Header) { "$($response.Headers[$Header])" | Should -Match $Pattern }
    }
  }

  Context 'Asset exposure' {
    It 'does not serve <Path>' -ForEach $privatePaths {
      (Invoke-Probe -Url "$($config.BaseUrl)$Path").StatusCode | Should -Be 404
    }
  }
}
