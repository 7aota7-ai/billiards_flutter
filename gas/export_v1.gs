/**
 * export_v1.gs
 *
 * 全シートをJSONファイルとしてGoogle Driveへエクスポートする読み取り専用スクリプト。
 * AI（ChatGPT / Claude）にSpreadsheet全体を共有するために使う。
 *
 * - シートへの書き込みは一切行わない
 * - system_v2.gs とは独立して動作する
 * - 実行方法：Apps Scriptエディタで exportAllSheetsToJson を実行
 *   → ログに出力ファイルのURLが表示される
 */

const EXPORT_FOLDER_NAME = "billiards_exports";
const EXPORT_SCHEMA_VERSION = "export-1.0";

/**
 * 全シートをJSON化してDriveに保存し、ファイルURLをログに出す。
 */
function exportAllSheetsToJson() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const payload = {
    export_schema_version: EXPORT_SCHEMA_VERSION,
    spreadsheet_name: ss.getName(),
    spreadsheet_id: ss.getId(),
    exported_at: Utilities.formatDate(new Date(), "Asia/Tokyo", "yyyy-MM-dd HH:mm:ss"),
    sheets: []
  };

  ss.getSheets().forEach(function (sheet) {
    const range = sheet.getDataRange();
    // getDisplayValues: 数式は計算結果、日付は表示形式の文字列で取得する
    // （数式・入力規則には触れない読み取りのみ）
    const values = range.getDisplayValues();
    payload.sheets.push({
      name: sheet.getName(),
      row_count: values.length,
      column_count: values.length > 0 ? values[0].length : 0,
      values: values
    });
  });

  const folder = getOrCreateExportFolder_();
  const fileName = "billiards_export_" +
    Utilities.formatDate(new Date(), "Asia/Tokyo", "yyyyMMdd_HHmmss") + ".json";
  const file = folder.createFile(fileName, JSON.stringify(payload, null, 1), MimeType.PLAIN_TEXT);

  Logger.log("[OK] エクスポート完了");
  Logger.log("[OK] シート数: " + payload.sheets.length);
  Logger.log("[OK] ファイル: " + file.getUrl());
  return file.getUrl();
}

/**
 * 指定シートのみエクスポートする（容量を抑えたいとき用）。
 * 例: exportSheetsToJson(["Position Lab", "練習ログ", "課題管理"])
 */
function exportSheetsToJson(sheetNames) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const payload = {
    export_schema_version: EXPORT_SCHEMA_VERSION,
    spreadsheet_name: ss.getName(),
    spreadsheet_id: ss.getId(),
    exported_at: Utilities.formatDate(new Date(), "Asia/Tokyo", "yyyy-MM-dd HH:mm:ss"),
    sheets: []
  };

  sheetNames.forEach(function (name) {
    const sheet = ss.getSheetByName(name);
    if (!sheet) {
      // シート名の推測はしない。存在しない名前は明示的にエラーにする
      throw new Error("[ERROR] シートが存在しません: " + name);
    }
    const values = sheet.getDataRange().getDisplayValues();
    payload.sheets.push({
      name: sheet.getName(),
      row_count: values.length,
      column_count: values.length > 0 ? values[0].length : 0,
      values: values
    });
  });

  const folder = getOrCreateExportFolder_();
  const fileName = "billiards_export_partial_" +
    Utilities.formatDate(new Date(), "Asia/Tokyo", "yyyyMMdd_HHmmss") + ".json";
  const file = folder.createFile(fileName, JSON.stringify(payload, null, 1), MimeType.PLAIN_TEXT);

  Logger.log("[OK] 部分エクスポート完了: " + sheetNames.join(", "));
  Logger.log("[OK] ファイル: " + file.getUrl());
  return file.getUrl();
}

/**
 * エクスポート先フォルダを取得（なければマイドライブ直下に作成）。
 */
function getOrCreateExportFolder_() {
  const folders = DriveApp.getFoldersByName(EXPORT_FOLDER_NAME);
  if (folders.hasNext()) {
    return folders.next();
  }
  return DriveApp.createFolder(EXPORT_FOLDER_NAME);
}
