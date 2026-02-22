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

<!-- BEGIN MCIX-ACTION-DOCS -->
# MCIX datastage import action

Runs mcix datastage import

> Namespace: `datastage`<br>
> Action: `import`<br>
> Usage: `${{ github.repository }}/datastage/import@v1`

... where `v1` is the version of the action you wish to use.

---

## 🚀 Usage

Minimal example:

```yaml
jobs:
  datastage-import:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Run MCIX datastage import action
        id: datastage-import
        uses: ${{ github.repository }}/datastage/import@v1
        with:
          api-key: <required>
          url: <required>
          user: <required>
          # assets: <optional>
          # project: <optional>
          # project-id: <optional>
```

---

### Project selection rules

- Provide **exactly one** of `project` or `project-id`.
- If both are supplied, the action should fail fast (ambiguous).

---

## 🔧 Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `api-key` | ✅ |  | API key for authentication |
| `url` | ✅ |  | URL of the DataStage server |
| `user` | ✅ |  | Username for authentication |
| `assets` | ❌ |  | Path to the DataStage assets to import |
| `project` | ❌ |  | DataStage project name |
| `project-id` | ❌ |  | DataStage project id |

---

## 📤 Outputs

| Name | Description |
| --- | --- |
| `return-code` | The return code of the command |

---

## 🧱 Implementation details

- `runs.using`: `docker`
- `runs.image`: `Dockerfile`

---

## 🧩 Notes

- The sections above are auto-generated from `action.yml`.
- To edit this documentation, update `action.yml` (name/description/inputs/outputs).
<!-- END MCIX-ACTION-DOCS -->
