# GAS Design v1.0

## 目的

本ドキュメントは、ビリヤード競技力向上システムにおける GAS の処理設計を定義する。

GAS は、ChatGPT または将来の Flutter アプリから渡される JSON を受け取り、Google Spreadsheet の各シートを更新する役割を持つ。

GAS は業務ロジックを勝手に判断しない。処理対象・更新方式・列名は `json-spec-v1.md` と `spreadsheet-design.md` に従う。

---

## 基本方針

- JSON仕様を最上位のデータ仕様とする
- JSONキーとシート列名は原則一致させる
- シート列順には依存しない
- 1シート1役割を崩さない
- 実行結果ログで、どのシート・どのキー・どの行で失敗したか確認できるようにする
- Today's Focus は表示用シートと履歴シートを分けて処理する

---

## 処理全体フロー

```text
JSON受信
  ↓
JSON構文チェック
  ↓
schema_version確認
  ↓
run設定確認
  ↓
各JSONキーを順番に処理
  ↓
Append / Upsert / Replace 実行
  ↓
Today's Focus表示更新
  ↓
Today's Focus履歴追加
  ↓
処理ログ出力
  ↓
完了
```

---

## schema_version

JSONには必ず `schema_version` を含める。

```json
{
  "schema_version": "1.0.0"
}
```

v1.0では、GASは `1.0.0` を想定する。

許可されていないバージョンが渡された場合は処理を停止する。

---

## run設定

JSON内の `run` で処理対象を制御する。

例：

```json
{
  "run": {
    "training_records": true,
    "mist_logs": false,
    "today_focus": true
  }
}
```

`true` のものだけ処理する。

`run` に存在しないキーは処理しない。

---

## 更新方式

GASで使用する更新方式は3種類に限定する。

| 更新方式 | 意味 |
|---|---|
| Append | 末尾に追加する |
| Upsert | キーがあれば更新、なければ追加する |
| Replace | 表示領域を置き換える |

---

## JSONキー別処理

| JSONキー | 対象シート | 更新方式 | キー |
|---|---|---|---|
| menu_plans | 練習設計 | Append | なし |
| training_records | 練習記録 | Append | なし |
| match_reviews | 試合振り返り | Append | なし |
| mist_logs | ミスログ | Append | なし |
| issue_updates | 課題管理 | Upsert | 課題 |
| decision_updates | 決定事項 | Upsert | ID |
| reference_updates | リファレンス | Upsert | ID |
| variation_map_records | 変化量マップ | Append | なし |
| today_focus | Today's Focus | Replace | なし |
| today_focus | Today's Focus履歴 | Append | なし |

---

## Append処理

対象配列の各オブジェクトを、対象シートの末尾に追加する。

処理対象：

- menu_plans
- training_records
- match_reviews
- mist_logs
- variation_map_records
- Today's Focus履歴

### 仕様

- シート1行目をヘッダーとして扱う
- JSONキーと同名の列に値を入れる
- JSONに存在しない列は空欄
- シートに存在しないJSONキーは原則無視する
- 必須列がない場合はエラーとする

---

## Upsert処理

キー列の値で既存行を検索し、該当行があれば更新、なければ新規追加する。

処理対象：

- issue_updates
- decision_updates
- reference_updates

### 仕様

- キー列がシートに存在しない場合はエラー
- キー値が空の場合はエラー
- 既存行が1件見つかった場合は更新
- 既存行が見つからない場合は末尾に追加
- 複数行見つかった場合はエラー

### 課題管理の注意

v1.0では `課題` をキーとする。

課題名は自然言語のため揺れが発生しやすい。GAS実装では最低限、以下を正規化して照合する。

- 前後空白の除去
- 全角スペースの半角化
- 連続スペースの圧縮

課題ID管理は将来検討事項とする。

---

## Replace処理

Today's Focus 表示用シートを固定レイアウトとして更新する。

処理対象：

- today_focus → Today's Focus

### 仕様

- Today's Focus は通常の表形式シートとして扱わない
- 固定セルまたは固定ブロックに書き込む
- 既存表示内容は更新時に置き換える
- 同じ today_focus データを Today's Focus履歴 にも Append する

---

## Today's Focus 保存形式

Today's Focus履歴では、配列フィールドを以下の形式で保存する。

| データ型 | 保存形式 |
|---|---|
| 文字列 | そのまま保存 |
| 配列 | 改行区切りテキストで保存 |
| オブジェクト配列 | v1.0ではJSON文字列で保存 |

理由：

- v1.0ではSpreadsheet上で人が読むことを優先する
- 改行区切りであれば視認性が高い
- Flutter側では改行区切り文字列を配列へ戻せる

---

## リファレンス更新方針

`reference_updates` は変化量マップと同じID体系を使う。

以下の項目はIDで保存する。

- 厚みID
- 撞点上下
- 撞点左右
- 転がりイメージ

的球位置・手球位置・狙い穴など、変化量マップに存在しない項目は、ChatGPTが補完できる場合のみ入力する。補完できない場合は空欄のまま登録する。

---

## エラー処理

GASは以下の場合にエラーを出す。

| エラー | 内容 |
|---|---|
| JSON構文エラー | JSONとして解析できない |
| schema_version不一致 | 対応外のバージョン |
| シート不存在 | 対象シートが見つからない |
| キー列不存在 | Upsert対象のキー列がない |
| キー値空欄 | Upsert対象のキー値が空 |
| 重複キー | Upsert対象の既存行が複数存在する |
| 必須列不足 | 必須項目に対応する列がない |
| 値制約違反 | プルダウンなどの許可値外 |

---

## ログ仕様

GASは処理ログを出力する。

### 正常時ログ例

```text
[START] updateBilliardsSheets
[OK] schema_version=1.0.0
[OK] training_records: 2件 Append
[OK] mist_logs: 6件 Append
[OK] issue_updates: 3件 Upsert
[OK] today_focus: Replace
[OK] today_focus_history: Append
[END] 正常終了
```

### エラー時ログ例

```text
[ERROR] issue_updates
シート: 課題管理
キー列: 課題
キー値: 薄めカット
原因: キー列「課題」が存在しません
```

---

## 実装上の注意

- シート列順に依存しない
- ヘッダー名で列を特定する
- 既存シートの列追加に強い設計にする
- 新しいJSONキーを追加する場合は、先に `json-spec-v1.md` を更新する
- 新しいシートを追加する場合は、先に `spreadsheet-design.md` を更新する
- GASだけで仕様を先行変更しない

---

## v1.0で実装しないこと

以下はv1.0では実装しない。

- 課題IDによる課題管理
- リファレンス自動昇格
- 複雑な課題タグ名寄せ
- DB連携
- Flutter API化

これらは `docs/decisions/future-considerations.md` で管理する。
