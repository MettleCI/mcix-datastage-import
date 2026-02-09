# MCIX DataStage Import GitHub Action

Import DataStage NextGen assets into a target project using MCIX.

> Namespace: `datastage`  
> Action: `import`  
> Usage: `DataMigrators/mcix/datastage/import@v1`

... where `v1` is the version of the action you wish to use.

## 🚀 Usage

```yaml
- uses: DataMigrators/mcix/datastage/import@v1
  with:
    api-key: ${{ secrets.MCIX_API_KEY }}
    url: https://your-mcix-server/api
    user: dm-automation
    assets: ./datastage/assets/MyFlow.json
    project: GitHub_CP4D_DevOps
```

## 🔧 Inputs

| Name         | Required | Description |
|--------------|----------|-------------|
| api-key      | Yes      | MCIX API key |
| url          | Yes      | MCIX server URL |
| user         | Yes      | Logical MCIX user |
| assets       | Yes      | Asset file(s) to import |
| project      | Conditional | Project name |
| project-id   | Conditional | Project ID |

## 📤 Outputs

| Name | Description |
|------|-------------|
| return-code | Exit code |

## 📚 More information

See https://nextgen.mettleci.io/mettleci-cli/datastage-namespace/#datastage-import

