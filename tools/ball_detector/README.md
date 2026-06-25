# Ball detector (OpenCV prototype)

斜めの台写真から球位置を検出し、正規化座標 JSON を出力します。

## セットアップ

```bash
cd tools/ball_detector
python -m venv .venv
.venv\Scripts\activate        # Windows
pip install -r requirements.txt
```

## Flutter アプリ

### カメラ（配置を取る）

| 環境 | カメラ | App Store |
|------|--------|-----------|
| **Web URL（HTTPS）** | ✅ スマホブラウザで可（カメラ許可） | **不要** |
| **PWA / ホーム画面追加** | ✅ 同上 | **不要** |
| **ネイティブ APK / IPA** | ✅ | Store 公開は任意（ sideload / TestFlight 可） |

- **App Store 登録は必須ではありません。** 今まで通り GitHub Pages の URL から開いても、スマホブラウザでカメラが使えます。
- Web では最初に **「カメラプレビューを起動」** をタップ（ブラウザのユーザー操作が必要）。
- プレビューが動かない場合は **「ブラウザカメラで撮影」**（OS 標準カメラ UI）を試してください。
- **球検出 API** は PC 上の `127.0.0.1:8765` のため、スマホ単体では届きません（同一 Wi‑Fi + PC IP 設定が別途必要）。

### その他

- **写真から読込** … ギャラリー画像＋4隅タップ（PC / Web 含む）。

```bash
# 検出 API を別ターミナルで起動してからアプリで「撮影して検出」
cd tools/ball_detector
.venv\Scripts\uvicorn.exe server:app --host 127.0.0.1 --port 8765
```

### ガイド寸法

- 外寸参考: 290 × 160 cm
- プレイングエリア: **254 × 127 cm（2:1）**
- カメラ枠: 手前幅 100% / 遠い側 64% の台形（`lib/models/table_guide_geometry.dart`）

## CLI 使い方

### 1. 対話的に4隅を指定

```bash
python detect_balls.py -i samples/table_photo.png --pick-corners -o out/result.json --debug-dir out
```

台フェルト内側の4隅を **左上 → 右上 → 右下 → 左下** の順にクリック。  
`R` でリセット、`ESC` で確定。

### 2. JSON で4隅を指定

`corners.json`:

```json
[
  [120, 680],
  [1180, 620],
  [1050, 120],
  [80, 180]
]
```

```bash
python detect_balls.py -i samples/table_photo.png -c corners.json -o out/result.json
```

## 出力 JSON

**Flutter に貼り付けるときは CLI が出力した JSON をそのまま使ってください。**  
README の `[...]` などは省略記号で、JSON としては無効です。

### Flutter 貼り付け用（コピー可）

```json
{
  "balls": [
    { "id": null, "x": 0.312, "y": 0.548, "color": "yellow" },
    { "id": null, "x": 0.697, "y": 0.241, "color": "white" },
    { "id": null, "x": 0.159, "y": 0.271, "color": "purple" }
  ]
}
```

`meta` は省略しても読み込めます。`balls` 配列だけでも OK です。

### CLI 実行後の完全な出力例

`samples/paste_example.json` または `detect_balls.py -o out/result.json` の中身:

```json
{
  "balls": [
    { "id": null, "x": 0.312, "y": 0.548, "color": "yellow" }
  ],
  "meta": {
    "source_image": "table_photo.png",
    "warp_size": [2000, 1000],
    "corners": [[195, 155], [575, 155], [685, 885], [85, 885]],
    "corner_order": ["top-left", "top-right", "bottom-right", "bottom-left"],
    "ball_count": 8
  }
}
```

- `x`, `y`: フェルト上の正規化座標 (0–1)。Flutter エディタと同じ座標系。
- `id`: v1 は常に `null`（球種はユーザー確認）。
- `color`: HSV による色ヒント（半自動）。

## FastAPI サーバー（Flutter 連携）

```bash
uvicorn server:app --reload --host 0.0.0.0 --port 8765
```

`POST /detect` — multipart:

- `image`: 写真ファイル
- `corners`: JSON 文字列 `[[x,y], ...]`

## Flutter 連携

### カメラ（配置を取る）

| 環境 | カメラ | App Store |
|------|--------|-----------|
| **Web URL（HTTPS）** | ✅ スマホブラウザで可 | **不要** |
| **PWA / ホーム画面追加** | ✅ 同上 | **不要** |
| **ネイティブ APK / IPA** | ✅ | Store 公開は任意 |

- GitHub Pages の URL から開いても、スマホブラウザでカメラが使えます（HTTPS + カメラ許可）。
- Web では **「カメラプレビューを起動」** をタップしてから撮影（ブラウザの仕様）。
- プレビュー不可の場合は **「ブラウザカメラで撮影」** を試してください。
- 球検出 API は PC 上の `127.0.0.1:8765` のため、スマホ単体では届きません（同一 Wi‑Fi + PC IP が別途必要）。

### 写真から読込

1. 配置エディタ → **写真から読込**
2. 写真選択 → 4点タップ → 検出（ローカル API または JSON 貼り付け）
3. プレビュー確認 → エディタへ反映（id 未確定の球は色ヒント付きで配置）

デフォルト API: `http://127.0.0.1:8765`
