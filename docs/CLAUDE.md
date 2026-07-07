# CLAUDE.md

このファイルはClaudeへの不変の指示である。設計詳細・フェーズ・仕様は各docsを参照すること。

---

## 作業前に必ず参照するドキュメント

コード・JSON・Spreadsheet・仕様書を変更する前に、対象に応じて以下を確認する。

| ドキュメント | 参照タイミング |
|---|---|
| `docs/architecture/system-overview.md` | プロジェクト全体・フェーズ・シート構成を確認するとき |
| `docs/architecture/json-spec-v2.md` | JSONキー・データ型を確認・変更するとき |
| `docs/architecture/spreadsheet-design.md` | Spreadsheetの列・構造を変更するとき |
| `docs/architecture/gas-design.md` | GASの処理・設計を変更するとき |
| `docs/decisions/decisions_v2.md` | 設計判断の根拠を確認するとき |

---

## 絶対禁止事項

以下はいかなる場合も行わない。

### シート名
- 実シート名以外を使わない（実シート名は `system-overview.md` を参照）
- `練習設計` は使わない（正：`メニュー設計`）
- Reviewシートを新設しない

### データ保護
- 入力規則を `clearDataValidations()` で壊さない
- 数式列を値で上書きしない
- シート全体を不用意に `clear()` しない

### 数式列（上書き禁止）
`課題管理` シートの以下の列は数式列として扱う：
- 発生日 / 発生回数 / 成功率(%) / 最終更新日 / Today's Focus表示

`決定事項` シートの `Today's Focus表示` が数式の場合も上書きしない。

### Today's Focus履歴
- `Today's Focus`（表示用）の縦型テンプレートを `Today's Focus履歴` にそのまま貼らない
- `Today's Focus履歴` は横持ち1行追記のみ

### GAS
- 既存GASへ場当たり関数を追加しない
- Reference候補を勝手に正式Reference化しない
- エラーを黙って無視しない

---

## 出力方針

- 問題点は明確に指摘する
- 既存設計と現行Spreadsheetがズレている場合は、現行Spreadsheet実態を確認してから判断する
- 実装よりも保守性を優先する
- 追加提案は必要な場合だけ行う
- 推測で列・JSONキー・シートを追加しない（先に設計書を更新する）
