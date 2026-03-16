# Fabric Paginated Report Inventory

A PowerShell script that inventories **paginated report datasets** across Microsoft Fabric / Power BI workspaces. It exports each report's RDL definition and extracts authored SQL, stored procedures, datasource metadata, and field names into CSV and JSON files.

## Output Fields

| Field | Description |
|-------|-------------|
| WorkspaceId | Workspace GUID |
| WorkspaceName | Workspace display name |
| ReportId | Paginated report GUID |
| ReportName | Report display name |
| ReportWebUrl | URL to the report in the Power BI service |
| DatasetName | Dataset name from the RDL definition |
| DataSourceName | Data source reference name in the RDL |
| CommandType | Query command type (Text, StoredProcedure, etc.) |
| CommandText | The SQL query or stored procedure name |
| FieldNames | Comma-separated list of dataset field names |
| DataProvider | Data provider from the RDL (e.g., SQL, OLEDB) |
| ConnectionString | Connection string from the RDL |
| DatasourceType | Datasource type from the Power BI API |
| Server | Server name from the Power BI API |
| Database | Database name from the Power BI API |

## Prerequisites

```powershell
Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -Force
```

## Authentication

Before running the script, authenticate to Power BI:

```powershell
Connect-PowerBIServiceAccount
```

## Usage

```powershell
# Inventory workspaces you have access to
.\PaginatedReportInventory.ps1

# Inventory all workspaces tenant-wide (requires Fabric admin)
.\PaginatedReportInventory.ps1 -UseAdminApis

# Limit to first N reports (useful for testing)
.\PaginatedReportInventory.ps1 -UseAdminApis -MaxReports 2

# Specify a custom output folder
.\PaginatedReportInventory.ps1 -OutputRoot "C:\MyOutput"
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-OutputRoot` | String | `.\PaginatedReportInventory` | Folder to write output files |
| `-UseAdminApis` | Switch | Off | Use admin endpoints to list all tenant workspaces |
| `-MaxReports` | Int | `0` (unlimited) | Cap the number of reports exported (for testing) |

## Output

The script creates two files in the output folder:

- `paginated_report_datasets.csv` — CSV with all dataset records
- `paginated_report_datasets.json` — JSON with the same data

Exported RDL files are saved in a `RDL` subfolder within the output directory.

## Notes

- Personal workspaces (`PersonalGroup` type) are automatically skipped when using `-UseAdminApis`
- The script suppresses noisy MSAL warnings from the `MicrosoftPowerBIMgmt` module
- Requires PowerShell 5.1+ or PowerShell 7+
