# Fabric Paginated Report Inventory

PowerShell scripts that inventory **paginated report datasets** across Microsoft Fabric / Power BI workspaces. They export each report's RDL definition and extract authored SQL, stored procedures, datasource metadata, and field names into CSV and JSON files.

Two versions are included:

| Script | Authentication |
|--------|---------------|
| `PaginatedReportInventory.ps1` | Interactive login (browser-based) |
| `PaginatedReportInventory-SP.ps1` | Service principal (client secret or certificate) |

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
# Only if using Azure Key Vault:
Install-Module -Name Az.Accounts -Scope CurrentUser -Force
Install-Module -Name Az.KeyVault -Scope CurrentUser -Force
```

## Usage — Interactive Login

Authenticate first, then run the script:

```powershell
Connect-PowerBIServiceAccount

# Inventory workspaces you have access to
.\PaginatedReportInventory.ps1

# Inventory all workspaces tenant-wide (requires Fabric admin)
.\PaginatedReportInventory.ps1 -UseAdminApis

# Limit to first N reports (useful for testing)
.\PaginatedReportInventory.ps1 -UseAdminApis -MaxReports 2

# Specify a custom output folder
.\PaginatedReportInventory.ps1 -OutputRoot "C:\MyOutput"
```

## Usage — Service Principal

No pre-authentication needed; credentials are passed as parameters:

```powershell
# With client secret passed directly
.\PaginatedReportInventory-SP.ps1 -TenantId "your-tenant-id" `
  -ClientId "your-client-id" -ClientSecret "your-secret" -UseAdminApis

# With Azure Key Vault (recommended — avoids secrets in scripts/history)
Connect-AzAccount
.\PaginatedReportInventory-SP.ps1 -TenantId "your-tenant-id" `
  -ClientId "your-client-id" -KeyVaultName "my-keyvault" -SecretName "pbi-sp-secret" -UseAdminApis

# With max reports limit
.\PaginatedReportInventory-SP.ps1 -TenantId "your-tenant-id" `
  -ClientId "your-client-id" -ClientSecret "your-secret" -UseAdminApis -MaxReports 5
```

### Service Principal Setup

1. Register an app in **Azure AD / Entra ID**
2. Create a client secret and store it in **Azure Key Vault** (recommended)
3. In **Power BI Admin Portal → Tenant settings**, enable:
   - *"Service principals can use Fabric APIs"*
4. Add the service principal to a security group allowed in that setting
5. Grant the calling identity **Get** permission on the Key Vault secret (if using Key Vault)

## Parameters

### Interactive version (`PaginatedReportInventory.ps1`)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-OutputRoot` | String | `.\PaginatedReportInventory` | Folder to write output files |
| `-UseAdminApis` | Switch | Off | Use admin endpoints to list all tenant workspaces |
| `-MaxReports` | Int | `0` (unlimited) | Cap the number of reports exported (for testing) |

### Service Principal version (`PaginatedReportInventory-SP.ps1`)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-TenantId` | String | *(required)* | Azure AD / Entra ID tenant ID |
| `-ClientId` | String | *(required)* | Application (client) ID |
| `-ClientSecret` | String | — | Client secret (provide this **or** `-KeyVaultName`/`-SecretName`) |
| `-KeyVaultName` | String | — | Azure Key Vault name containing the secret |
| `-SecretName` | String | — | Secret name in Key Vault (required with `-KeyVaultName`) |
| `-OutputRoot` | String | `.\PaginatedReportInventory` | Folder to write output files |
| `-UseAdminApis` | Switch | Off | Use admin endpoints to list all tenant workspaces |
| `-MaxReports` | Int | `0` (unlimited) | Cap the number of reports exported (for testing) |

## Output

The script creates two files in the output folder:

- `paginated_report_datasets.csv` — CSV with all dataset records
- `paginated_report_datasets.json` — JSON with the same data

Exported RDL files are saved in a `rdl` subfolder within the output directory.

## Notes

- Personal workspaces (`PersonalGroup` type) are automatically skipped when using `-UseAdminApis`
- The scripts suppress noisy MSAL warnings from the `MicrosoftPowerBIMgmt` module
- Requires PowerShell 5.1+ or PowerShell 7+
