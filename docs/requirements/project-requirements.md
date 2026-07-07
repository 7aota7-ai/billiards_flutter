# プロジェクト要求仕様 v2.0

## プロジェクト名

ビリヤード競技力向上システム

## 目的

本システムは、練習・試合・Position Lab・プロ動画から得た知識を蓄積し、
**試合中に自然な判断ができる状態**を作ることを目的とする。

## システム構成

    ChatGPT / Claude Code
            ↓
    JSON v2
            ↓
    system_v2.gs
            ↓
    Google Spreadsheet

将来的には Flutter / API からも同じ JSON を利用する。

## 現在の実シート

-   使い方
-   判断基準
-   マスタ
-   練習記録_archive
-   メニュー設計
-   変化量マップ_archive
-   Position Lab
-   Pro Reference
-   練習ログ
-   Today's Focus
-   Today's Focus履歴
-   試合振り返り
-   ミスログ
-   課題管理
-   決定事項
-   リファレンス
-   集計
-   \_集計補助

## 基本ワークフロー

    練習・試合
     ↓
    振り返り
     ↓
    JSON生成
     ↓
    system_v2.gs
     ↓
    Spreadsheet更新
     ↓
    Today's Focus生成
     ↓
    次回練習

## 設計原則

1.  JSONを唯一のデータ契約とする
2.  実シート・実ヘッダーを正とする
3.  1シート1役割を徹底する
4.  Position Labは実験、Referenceは確定知識
5.  Pro Referenceはプロ動画知識を管理する
6.  Today's Focusは表示用、履歴は分析用
7.  GASはヘッダー名ベースで更新する
8.  数式・入力規則・テンプレートを保護する

## 更新方式

  方式      用途
  --------- -------------------------------
  Append    履歴追加
  Upsert    課題・決定事項・Reference更新
  Replace   Today's Focus表示

## v2.0実装方針

-   新規 `system_v2.gs` を正とする
-   旧GASは削除せず実行対象から外す
-   clear() によるテンプレート破壊を禁止
-   clearDataValidations() を通常処理で使用しない
-   数式列は値で上書きしない
-   ヘッダー名で列を特定する

## v2.0では実装しない

-   Flutter UI
-   DB移行
-   Reference自動昇格
-   課題ID運用
-   AIによる名寄せ
