# GAS Design v2.1

## 目的

本ドキュメントは、ビリヤード競技力向上システムにおけるGASの処理設計を定義する。

GASは、ChatGPTまたは将来のFlutterアプリから渡されるJSONを受け取り、Google Spreadsheetの各シートを更新する役割を持つ。

---

## 現在フェーズ

現在は **既存GAS修正ではなく、system_v2.gs の新規構築** を行う。

旧GASは複数ファイルに分散し、以下のリスクがある。

- 実シート名不一致
- 入力規則を壊す処理
- 数式列の上書き
- Today's Focus履歴の縦貼り崩れ
- どの関数が最新か不明

方針：

```text
旧GAS：削除しない・実行しない
新GAS：system_v2.gs
読み取り専用：export_v1.gs（リポジトリ gas/export_v1.gs で管理）
```

### export_v1.gs（読み取り専用エクスポート）

AIにSpreadsheet全体を共有するための読み取り専用スクリプト。書き込み処理を一切含まないため、本ドキュメントの数式列保護・入力規則保護の制約に抵触しない。

- `exportAllSheetsToJson()`：全シートを1つのJSONファイルとしてDriveの `billiards_exports` フォルダへ出力する
- `exportSheetsToJson(sheetNames)`：指定シートのみ出力する
- 値は `getDisplayValues()` で取得する（数式は計算結果、日付は表示形式の文字列）
- 固定レイアウトシート（Today's Focus等）も生のグリッドとしてそのまま出力する

---

## 基本方針

- JSON仕様を最上位のデータ仕様とする
- 現行Spreadsheet実シート名を使用する
- シート列順には依存しない
- ヘッダー名で列を特定する
- 1シート1役割を崩さない
- 数式列を上書きしない
- 入力規則を壊さない
- Today's Focusは表示用シートと履歴シートを分けて処理する
- エラー時に原因を追えるログを出す

---

## シート名定数

system_v2.gsでは必ず以下を定義する。

```javascript
const SHEETS = {
  USAGE: "使い方",
  JUDGEMENT: "判断基準",
  MASTER: "マスタ",
  PRACTICE_RECORD_ARCHIVE: "練習記録_archive",
  MENU_DESIGN: "メニュー設計",
  VARIATION_MAP_ARCHIVE: "変化量マップ_archive",
  POSITION_LAB: "Position Lab",
  PRO_REFERENCE: "Pro Reference",
  PRACTICE_LOG: "練習ログ",
  TODAY_FOCUS_HISTORY: "Today's Focus履歴",
  MATCH_REVIEW: "試合振り返り",
  MISS_LOG: "ミスログ",
  CHALLENGE: "課題管理",
  DECISION: "決定事項",
  REFERENCE: "リファレンス",
  TODAYS_FOCUS: "Today's Focus",
  SUMMARY: "集計",
  SUMMARY_HELPER: "_集計補助"
};
```

禁止：

```javascript
getSheetByName("練習設計")
```

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
シート存在チェック
  ↓
ヘッダー取得
  ↓
各JSONキーを順番に処理
  ↓
Append / Upsert / Replace 実行
  ↓
Today's Focus表示更新
  ↓
Today's Focus履歴1行追記
  ↓
処理ログ出力
```

---

## schema_version

GASは `2.0` のみ処理する。  
旧 `1.x` は互換対応しない（許可されていないバージョンとして処理を停止する）。

---

## JSONキー別処理

| JSONキー | 対象シート | 更新方式 | キー |
|---|---|---|---|
| menu_plans | メニュー設計 | Append | なし |
| training_records | 練習ログ | Append | なし |
| match_reviews | 試合振り返り | Append | なし |
| miss_logs | ミスログ | Append | なし |
| issue_updates | 課題管理 | Upsert | 課題 |
| decision_updates | 決定事項 | Upsert | ID |
| position_lab_records | Position Lab | Append | なし |
| pro_reference_records | Pro Reference | Upsert | ID |
| reference_updates | リファレンス | Upsert | ID |
| today_focus | Today's Focus | Replace | なし |
| today_focus | Today's Focus履歴 | Append | なし |

`練習記録_archive`・`変化量マップ_archive` はManual運用とし、system_v2.gsからは書き込まない（Manual化に伴い `練習記録`・`変化量マップ` からリネーム済み）。

---

## Append処理

対象配列の各オブジェクトを、対象シートの末尾に追加する。

仕様：

- シート1行目をヘッダーとして扱う
- JSONキーと同名の列に値を入れる
- JSONに存在しない列は空欄
- シートに存在しないJSONキーは原則無視する
- 必須列がない場合はエラー
- 入力規則は削除しない

---

## Upsert処理

キー列の値で既存行を検索し、該当行があれば更新、なければ新規追加する。

仕様：

- キー列がシートに存在しない場合はエラー
- キー値が空の場合はエラー
- 既存行が1件見つかった場合は更新
- 既存行が見つからない場合は末尾に追加
- 複数行見つかった場合はエラー
- 更新禁止列は上書きしない

---

## Replace処理

Today's Focus表示用シートを固定レイアウトとして更新する。

仕様：

- Today's Focusは通常の表形式シートとして扱わない
- 固定セルまたは固定ブロックに書き込む
- テンプレート構造を壊さない
- 必要範囲のみ値を更新する
- 書式、列幅、罫線、入力規則を不用意に変更しない

---

## Today's Focus履歴

履歴は横持ち1行追記で保存する。

```text
日付
今日のテーマ
今日意識すること
今日の重点課題
今日の練習メニュー案
振り返り観点
明日以降の練習方針
登録日時
```

禁止：

```text
Today's Focusの縦型テンプレートをToday's Focus履歴へそのまま貼る
```

---

## 数式列保護

### 課題管理

以下は数式列として扱い、GASで値上書きしない。

```text
発生日
発生回数
成功率(%)
最終更新日
Today's Focus表示
```

### 決定事項

`Today's Focus表示` は数式運用される可能性があるため、原則GASで上書きしない。

---

## 入力規則保護

GASで以下を行わない。

```javascript
clearDataValidations()
```

値制約に引っかかる場合は、入力規則を壊すのではなく、出力値を既存候補に合わせる。

---

## 値変換

代表例：

| 入力 | 出力 |
|---|---|
| true | TRUEまたはチェックボックスTRUE |
| false | FALSEまたはチェックボックスFALSE |
| TodaysFocus表示 | Today's Focus表示 |
| 練習設計 | メニュー設計 |

プルダウン候補は `マスタ` または既存入力規則を正とする。

---

## ログ仕様

正常時ログ例：

```text
[START] updateBilliardsSheetsV2
[OK] schema_version=2.0
[OK] menu_plans: 5件 Append -> メニュー設計
[OK] issue_updates: 2件 Upsert -> 課題管理
[OK] today_focus: Replace -> Today's Focus
[OK] today_focus_history: Append -> Today's Focus履歴
[END] 正常終了
```

エラー時ログ例：

```text
[ERROR] issue_updates[2]
sheet=課題管理
mode=Upsert
key=課題
value=変化量マップ
reason=改善状況「新規」は許可値外
```

---

## 実装上の禁止事項

- 旧GASに追加関数を積み増さない
- シート全体を不用意に `clear()` しない
- 入力規則を `clearDataValidations()` で削除しない
- 数式列を値で上書きしない
- ヘッダー行を勝手に上書きしない
- シート名を推測しない
- Reviewシートを新設しない
- Reference候補を勝手に正式Reference化しない

---

## v2.1で実装しないこと

- 課題IDによる課題管理
- リファレンス自動昇格
- 複雑な課題タグ名寄せ
- DB連携
- Flutter API化
- 旧GASの完全削除
