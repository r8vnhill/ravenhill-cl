<#
.SYNOPSIS
  Helpers for the ravenhill.cl deployment tests (tests/Deployment.Tests.ps1).

.DESCRIPTION
  Keeps the test file declarative: configuration loading, repository file classification, HTTP
  probing, and content identity checks live here. Every function is side-effect free except for
  network requests made by Invoke-Probe.
#>

Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ContractPath = Join-Path $PSScriptRoot 'Deployment.Contract.psd1'

# Cloudflare Web Analytics inserts this tag right before </body> for browser-like clients.
$BeaconPattern = '<script[^>]*static\.cloudflareinsights\.com[^>]*></script>\r?\n(?=</body>)'

<#
.SYNOPSIS
  Returns the deployment contract merged with environment overrides.
.OUTPUTS
  Hashtable with the contract keys plus RepoRoot. BaseUrl has no trailing slash.
#>
function Get-DeploymentConfig {
  $config = Import-PowerShellDataFile -Path $ContractPath
  if ($env:RAVENHILL_BASE_URL) { $config.BaseUrl = $env:RAVENHILL_BASE_URL }
  if ($env:RAVENHILL_SOURCE_REF) { $config.SourceRef = $env:RAVENHILL_SOURCE_REF }
  $config.BaseUrl = $config.BaseUrl.TrimEnd('/')
  $config.RepoRoot = $RepoRoot
  $config
}

<#
.SYNOPSIS
  Lists repository files that a Workers Builds checkout would contain, relative to the repo root.
.DESCRIPTION
  Tracked files plus untracked, non-gitignored files, so new files are classified before they are
  committed. With -AssetIgnored, returns only the files matched by .assetsignore.
#>
function Get-RepositoryFile {
  param([switch] $AssetIgnored)
  [string[]] $filter = if ($AssetIgnored) {
    '-i', '--exclude-from=.assetsignore'
  } else {
    '--exclude-standard'
  }
  @(git -C $RepoRoot ls-files -c -o @filter)
}

<#
.SYNOPSIS
  Returns the effective (non-blank, non-comment) patterns in .assetsignore.
#>
function Get-AssetIgnorePattern {
  Get-Content -Path (Join-Path $RepoRoot '.assetsignore') |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') }
}

<#
.SYNOPSIS
  Lists URL paths (leading slash) that production must answer with 404.
.DESCRIPTION
  Every repository file that is not a public asset, plus the build checkout's git metadata.
#>
function Get-PrivateUrlPath {
  param([Parameter(Mandatory)][hashtable] $Config)
  $files = Get-RepositoryFile | Where-Object { $_ -notin $Config.PublicAssets }
  @($Config.GitMetadataPaths) + @($files) | ForEach-Object { "/$_" }
}

<#
.SYNOPSIS
  Sends one GET request without following redirects or throwing on 4xx/5xx.
#>
function Invoke-Probe {
  param([Parameter(Mandatory)][string] $Url)
  $params = @{
    Uri                = $Url
    MaximumRedirection = 0
    SkipHttpErrorCheck = $true
    ErrorAction        = 'SilentlyContinue'
    TimeoutSec         = 20
  }
  Invoke-WebRequest @params
}

<#
.SYNOPSIS
  Returns the raw response body decoded as UTF-8, independent of the declared charset.
#>
function Get-ResponseText {
  param([Parameter(Mandatory)] $Response)
  $buffer = [System.IO.MemoryStream]::new()
  try {
    $Response.RawContentStream.Position = 0
    $Response.RawContentStream.CopyTo($buffer)
    [System.Text.Encoding]::UTF8.GetString($buffer.ToArray())
  } finally {
    $buffer.Dispose()
  }
}

<#
.SYNOPSIS
  Removes the Cloudflare Web Analytics beacon that the edge injects into HTML responses.
.DESCRIPTION
  Restores the body as committed, so its git blob hash can be compared with the source.
#>
function ConvertTo-SourceHtml {
  param([Parameter(Mandatory)][string] $Html)
  [regex]::Replace($Html, $BeaconPattern, '')
}

<#
.SYNOPSIS
  Tests whether HTML contains the Cloudflare Web Analytics beacon.
#>
function Test-EdgeBeacon {
  param([Parameter(Mandatory)][string] $Html)
  [regex]::IsMatch($Html, $BeaconPattern)
}

<#
.SYNOPSIS
  Computes the git blob hash (SHA-1) of UTF-8 text, as `git hash-object --stdin` would.
#>
function Get-GitBlobHash {
  param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)
  $body = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($body.Length)`0")
  $hash = [System.Security.Cryptography.SHA1]::HashData([byte[]]($header + $body))
  [System.Convert]::ToHexString($hash).ToLowerInvariant()
}

<#
.SYNOPSIS
  Returns the git blob hash of a file at a ref, e.g. origin/main:index.html.
#>
function Get-SourceBlobHash {
  param(
    [Parameter(Mandatory)][string] $Ref,
    [Parameter(Mandatory)][string] $Path
  )
  git -C $RepoRoot rev-parse "${Ref}:$Path"
}

Export-ModuleMember -Function *
