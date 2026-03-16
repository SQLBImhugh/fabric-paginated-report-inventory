<#
.SYNOPSIS
  Paginated Report Dataset Inventory: extracts authored SQL/SP and datasource metadata from RDL definitions.

.DESCRIPTION
  - Lists workspaces (admin tenant-wide if -UseAdminApis, else only accessible workspaces)
  - Identifies paginated reports (format=RDL) in each workspace
  - Exports each RDL and parses dataset Query.CommandText, Query.CommandType, DataSourceName,
    DataProvider, ConnectionString, and field names
  - Retrieves datasource metadata from the Power BI API (type, server, database)
  - Outputs CSV and JSON files with enriched dataset information

.PARAMETER OutputRoot
  Folder to write outputs

.PARAMETER UseAdminApis
  Use admin endpoints to list all workspaces (requires Fabric admin or configured service principal)

.NOTES
  Prerequisites:
    Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -Force

  Before running, authenticate to Power BI:
    Connect-PowerBIServiceAccount

  Then run:
    .\PaginatedReportInventory.ps1
    .\PaginatedReportInventory.ps1 -UseAdminApis
    .\PaginatedReportInventory.ps1 -UseAdminApis -MaxReports 2
    .\PaginatedReportInventory.ps1 -OutputRoot "C:\MyOutput"
#>

param(
  [string]$OutputRoot = ".\PaginatedReportInventory",
  [switch]$UseAdminApis,
  [int]$MaxReports = 0   # 0 = unlimited; set to a positive number to cap reports exported (useful for testing)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
# Suppress noisy MSAL warnings emitted by the MicrosoftPowerBIMgmt module
$WarningPreference = "SilentlyContinue"

# ---------- Helpers ----------

function Get-PowerBIAccessTokenString {
  $authHeader = (Get-PowerBIAccessToken -WarningAction SilentlyContinue).Authorization
  if (-not $authHeader) { throw "Power BI access token not found. Run Connect-PowerBIServiceAccount first." }
  return $authHeader -replace '^Bearer\s+', ''
}

function Invoke-PbiRest {
  param(
    [string]$Method,
    [string]$RelativeUrl,
    $Body = $null
  )
  if ($null -eq $Body) {
    return Invoke-PowerBIRestMethod -Url $RelativeUrl -Method $Method -WarningAction SilentlyContinue | ConvertFrom-Json
  } else {
    $json = $Body | ConvertTo-Json -Depth 20
    return Invoke-PowerBIRestMethod -Url $RelativeUrl -Method $Method -Body $json -WarningAction SilentlyContinue | ConvertFrom-Json
  }
}

function Get-Workspaces {
  if ($UseAdminApis) {
    $top = 5000
    return (Invoke-PbiRest -Method Get -RelativeUrl "admin/groups?`$top=$top").value
  } else {
    return (Invoke-PbiRest -Method Get -RelativeUrl "groups").value
  }
}

function Get-PbiReportsInWorkspace {
  param([string]$WorkspaceId)
  return (Invoke-PbiRest -Method Get -RelativeUrl "groups/$WorkspaceId/reports").value
}

function Export-PaginatedReportRdl {
  param(
    [string]$WorkspaceId,
    [string]$ReportId,
    [string]$ReportName,
    [string]$RdlFolder
  )
  $safe = ($ReportName -replace '[\\/:*?"<>|]', '_')
  $path = Join-Path $RdlFolder "$safe.rdl"

  if (Test-Path $path) { Remove-Item -LiteralPath $path -Force }

  Invoke-PowerBIRestMethod `
    -Url "groups/$WorkspaceId/reports/$ReportId/Export" `
    -Method Get `
    -OutFile $path `
    -WarningAction SilentlyContinue | Out-Null

  return $path
}

function Get-PaginatedReportDatasources {
  param(
    [string]$WorkspaceId,
    [string]$ReportId
  )
  return (Invoke-PbiRest -Method Get -RelativeUrl "groups/$WorkspaceId/reports/$ReportId/datasources").value
}

function Parse-RdlDatasets {
  param(
    [string]$RdlPath,
    [string]$ReportName,
    [string]$WorkspaceId,
    [string]$WorkspaceName,
    [string]$ReportId,
    [string]$ReportWebUrl,
    [array]$ApiDatasources
  )
  [xml]$rdl = Get-Content -LiteralPath $RdlPath
  $out = @()

  # Build a lookup of RDL-embedded data sources: Name -> (DataProvider, ConnectString)
  $dsLookup = @{}
  try {
    $rdlDataSources = $rdl.Report.DataSources.DataSource
    foreach ($rds in $rdlDataSources) {
      $name = ""
      $provider = ""
      $connStr = ""
      try { $name     = $rds.Name } catch {}
      try { $provider = $rds.ConnectionProperties.DataProvider } catch {}
      try { $connStr  = $rds.ConnectionProperties.ConnectString } catch {}
      if ($name) {
        $dsLookup[$name] = @{ DataProvider = $provider; ConnectionString = $connStr }
      }
    }
  } catch {}

  # Build a lookup from API datasources by name (best-effort match)
  $apiLookup = @{}
  foreach ($ads in $ApiDatasources) {
    $apiName = ""
    try { $apiName = $ads.name } catch {}
    if ($apiName) {
      $apiLookup[$apiName] = $ads
    }
  }

  $datasets = $rdl.Report.DataSets.DataSet
  foreach ($ds in $datasets) {
    $dsName       = ""
    $cmdType      = $null
    $cmdText      = $null
    $dsSourceName = ""
    $fieldNames   = ""
    try { $dsName       = $ds.Name }                catch {}
    try { $cmdType      = $ds.Query.CommandType }    catch {}
    try { $cmdText      = $ds.Query.CommandText }    catch {}
    try { $dsSourceName = $ds.Query.DataSourceName } catch {}

    # Extract field names
    try {
      $fields = $ds.Fields.Field | ForEach-Object { $_.Name }
      $fieldNames = ($fields -join ", ")
    } catch {}

    # Resolve RDL datasource metadata
    $dataProvider = ""
    $connString   = ""
    if ($dsSourceName -and $dsLookup.ContainsKey($dsSourceName)) {
      $dataProvider = $dsLookup[$dsSourceName].DataProvider
      $connString   = $dsLookup[$dsSourceName].ConnectionString
    }

    # Resolve API datasource metadata
    $apiDsType  = ""
    $apiServer  = ""
    $apiDb      = ""
    if ($dsSourceName -and $apiLookup.ContainsKey($dsSourceName)) {
      $a = $apiLookup[$dsSourceName]
      try { $apiDsType = $a.datasourceType }                catch {}
      try { $apiServer = $a.connectionDetails.server }       catch {}
      try { $apiDb     = $a.connectionDetails.database }     catch {}
    } elseif ($ApiDatasources.Count -eq 1) {
      # Single datasource — safe to match
      $a = $ApiDatasources[0]
      try { $apiDsType = $a.datasourceType }                catch {}
      try { $apiServer = $a.connectionDetails.server }       catch {}
      try { $apiDb     = $a.connectionDetails.database }     catch {}
    }

    $out += [PSCustomObject]@{
      WorkspaceId      = $WorkspaceId
      WorkspaceName    = $WorkspaceName
      ReportId         = $ReportId
      ReportName       = $ReportName
      ReportWebUrl     = $ReportWebUrl
      DatasetName      = if ($dsName) { $dsName } else { "" }
      DataSourceName   = if ($dsSourceName) { $dsSourceName } else { "" }
      CommandType      = if ($cmdType) { "$cmdType" } else { "Text" }
      CommandText      = if ($cmdText) { "$cmdText".Trim() } else { "" }
      FieldNames       = $fieldNames
      DataProvider     = $dataProvider
      ConnectionString = $connString
      DatasourceType   = $apiDsType
      Server           = $apiServer
      Database         = $apiDb
    }
  }
  return $out
}

# ---------- Main ----------

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$rdlFolder = Join-Path $OutputRoot "rdl"
New-Item -ItemType Directory -Path $rdlFolder -Force | Out-Null

# Caller must have already run Connect-PowerBIServiceAccount
$null = Get-PowerBIAccessTokenString

$workspaces = Get-Workspaces
Write-Host "Found $($workspaces.Count) workspace(s)"

$dsOut = New-Object System.Collections.Generic.List[object]
$paginatedCount = 0

foreach ($ws in $workspaces) {
  $wsId   = $ws.id
  $wsName = $ws.name

  # Skip personal workspaces (type=PersonalGroup) — they don't support group report APIs
  $wsType = if ($ws.PSObject.Properties['type']) { $ws.type } else { $null }
  if ($wsType -eq "PersonalGroup") {
    Write-Host "Skipping personal workspace: $wsName" -ForegroundColor DarkGray
    continue
  }

  Write-Host "Workspace: $wsName ($wsId)"

  $reports = @()
  try {
    $reports = Get-PbiReportsInWorkspace -WorkspaceId $wsId
  } catch {
    Write-Host "WARNING: Could not list reports for workspace '$wsName': $($_.Exception.Message)" -ForegroundColor Yellow
    continue
  }
  foreach ($r in $reports) {
    $format = if ($r.PSObject.Properties['format']) { $r.format } else { $null }
    if ($format -ne "RDL") { continue }

    # Check max reports limit
    if ($MaxReports -gt 0 -and $paginatedCount -ge $MaxReports) {
      Write-Host "Reached -MaxReports limit ($MaxReports). Stopping." -ForegroundColor Cyan
      break
    }

    $paginatedCount++
    $webUrl = if ($r.PSObject.Properties['webUrl']) { $r.webUrl } else { "" }
    Write-Host "  Paginated report: $($r.name)"

    # Export RDL
    $rdlPath = Export-PaginatedReportRdl -WorkspaceId $wsId -ReportId $r.id -ReportName $r.name -RdlFolder $rdlFolder

    # Get API datasource metadata
    $apiDs = @()
    try {
      $apiDs = @(Get-PaginatedReportDatasources -WorkspaceId $wsId -ReportId $r.id)
    } catch {
      Write-Host "WARNING: Could not retrieve API datasources for $($r.name): $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Parse RDL datasets with all enrichment
    $parsed = Parse-RdlDatasets `
      -RdlPath $rdlPath `
      -ReportName $r.name `
      -WorkspaceId $wsId `
      -WorkspaceName $wsName `
      -ReportId $r.id `
      -ReportWebUrl $webUrl `
      -ApiDatasources $apiDs

    foreach ($row in $parsed) { $dsOut.Add($row) }
  }
  # Break out of workspace loop if max reports reached
  if ($MaxReports -gt 0 -and $paginatedCount -ge $MaxReports) { break }
}

# Write outputs
$csvPath  = Join-Path $OutputRoot "paginated_report_datasets.csv"
$jsonPath = Join-Path $OutputRoot "paginated_report_datasets.json"

$dsOut | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvPath
$dsOut | ConvertTo-Json -Depth 10 | Out-File $jsonPath -Encoding UTF8

Write-Host ""
Write-Host "Done. Found $paginatedCount paginated report(s) with $($dsOut.Count) dataset(s)."
Write-Host "Outputs: $csvPath"
Write-Host "         $jsonPath"
