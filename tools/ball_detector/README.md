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
| **Web URL（HTTPS）・スマホ** | ✅ プレビュー＋黄色ガイド | **不要** |
| **Web URL・PC ブラウザ** | ❌ プレビュー非対応（**写真から読込**を使用） | **不要** |
| **PWA / ホーム画面追加** | ✅ 同上 | **不要** |
| **ネイティブ APK / IPA** | ✅ | Store 公開は任意（ sideload / TestFlight 可） |

- **App Store 登録は必須ではありません。** 今まで通り GitHub Pages の URL から開いても、スマホブラウザでカメラが使えます。
- Web では最初に **「カメラプレビューを起動」** をタップ（ブラウザのユーザー操作が必要）。
- プレビューが動かない場合は **「ブラウザカメラで撮影」**（OS 標準カメラ UI）を試してください。
- **球検出 API** … 本番は Cloud Run（HTTPS）。ローカルは PC 上の uvicorn。

### スマホで撮影 → 検出

**本番（推奨）:** GitHub Pages の URL から開くだけ。Cloud Run API に HTTPS で接続します（下記「Cloud Run 本番デプロイ」参照）。

**ローカル開発（同一 Wi-Fi）:** GitHub Pages（HTTPS）からは HTTP API に届きません。**http://PCのIP:ポート** でアプリを開いてください。

1. PC: `uvicorn server:app --host 0.0.0.0 --port 8765`
2. PC: `flutter run -d chrome --web-hostname 0.0.0.0 --web-port 8080`
3. スマホ: `http://192.168.x.x:8080` を開く
4. **配置を取る** → API URL を `http://192.168.x.x:8765` → **接続** → 撮影

API 未接続時は撮影後 **写真から読込** に引き継ぎ（4隅はガイド値を自動設定）。

### その他

- **写真から読込** … ギャラリー画像＋4隅タップ（PC / Web 含む）。

```bash
# 検出 API を別ターミナルで起動してからアプリで「撮影して検出」
cd tools/ball_detector
.venv\Scripts\uvicorn.exe server:app --host 127.0.0.1 --port 8765
```

### 「API 未接続」になるとき（よくある原因）

| 開き方 | API に繋がる？ |
|--------|----------------|
| **GitHub Pages（HTTPS）+ Cloud Run** | ✅ HTTPS → HTTPS |
| **GitHub Pages + ローカル HTTP API** | ❌ mixed content |
| **PC で `flutter run -d chrome`（HTTP）+ ローカル API** | ✅ |
| **スマホ Web + ローカル API** | ❌（127.0.0.1 はスマホ自身） |

**ステップ 1（PC で撮影→検出）の正しい手順:**

1. ターミナル A: 上記 uvicorn を起動（閉じない）
2. ターミナル B: プロジェクト直下で `flutter run -d chrome`
3. 開いた **http://localhost** のアプリで「撮影して検出」

GitHub Pages では **Cloud Run（HTTPS）** がデフォルトです。ローカル uvicorn のみの場合は `flutter run`（HTTP）を使ってください。

### ガイド寸法

- 外寸参考: 290 × 160 cm
- プレイングエリア: **254 × 127 cm（2:1）**
- カメラ枠: 手前幅 **96%** / 遠い側 **37%** の台形（`lib/models/table_guide_geometry.dart`）  
  実店舗写真 `S__194969627_0.jpg`（背丈140cm・台から40cm・頭上気味）でキャリブレーション。プレビューは最小ズーム（広角）を初期値。

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

## 検出アルゴリズム (v0.1.5)

v0.1.5 の主な改善:

1. **緑台対応** — 青台だけでなく緑台のフェルトマスクを自動選択
2. **候補スコアリング** — サイズ・彩度・円周リング・反射除外で誤検出を抑制
3. **色分類** — 中心グレア回避のリングサンプリング＋ストライプ球対応
4. **CLAHE + 多段 Hough** — 照明ムラのある店舗写真で拾いやすく

### 後処理フィルタ

1. **フェルト内** — 台布マスク上のみ（中心＋円周サンプル）
2. **端除外** — 正規化座標で四辺から 6% 以内を除外
3. **距離で重複除去** — 平均半径 × 2.2 未満の近傍は高スコアのみ残す
4. **上限 12 個** — クッション付近の誤検出を優先的に落とす

`meta.ball_count_raw` にフィルタ前件数、`meta.filter` に除外内訳、`meta.detector_version` に検出器バージョンがあります。


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
| **Web URL（HTTPS）・スマホ** | ✅ プレビュー＋黄色ガイド | **不要** |
| **Web URL・PC ブラウザ** | ❌ **写真から読込** を使用 | **不要** |
| **PWA / ホーム画面追加** | ✅ 同上 | **不要** |
| **ネイティブ APK / IPA** | ✅ | Store 公開は任意 |

- GitHub Pages の URL から開いても、スマホブラウザでカメラが使えます（HTTPS + カメラ許可）。
- Web では **「カメラプレビューを起動」** をタップしてから撮影（ブラウザの仕様）。
- プレビュー不可の場合は **「ブラウザカメラで撮影」** を試してください。
- 球検出 API は **Cloud Run（HTTPS）** がデフォルト。ローカルは `--dart-define=DETECTION_API_URL=http://127.0.0.1:8765`。

### 写真から読込

1. 配置エディタ → **写真から読込**
2. 写真選択 → 4点タップ → 検出（ローカル API または JSON 貼り付け）
3. プレビュー確認 → エディタへ反映（id 未確定の球は色ヒント付きで配置）

デフォルト API: Cloud Run 本番（`lib/services/detection_api_settings.dart` の `cloudRunUrl`）。  
ローカル開発は `http://127.0.0.1:8765` または `--dart-define=DETECTION_API_URL=...`。

---

## デプロイ後も /health が 0.1.4 のまま

**ほぼ確実に `git pull` 前の古いコードをデプロイしています。**

`gcloud run deploy --source .` は **手元のファイル** をそのままビルドします。リモートの main が 0.1.5 でも、ローカルが 0.1.4 なら 0.1.4 がデプロイされます。

### 確認（デプロイ前）

```bash
cd billiards_flutter
git pull origin main
grep APP_VERSION tools/ball_detector/server.py
# => APP_VERSION = "0.1.5"  であること
```

### 再デプロイ（推奨: スクリプト）

```bash
bash tools/ball_detector/deploy.sh
```

成功すると `/health` が次のようになります:

```json
{"status":"ok","version":"0.1.5","git_sha":"f4cd5c5"}
```

`git_sha` が `unknown` の場合は古いリビジョンが動いている可能性があります。

### 手動デプロイ

```bash
cd billiards_flutter && git pull origin main
cd tools/ball_detector
export GIT_SHA=$(git -C ../.. rev-parse --short HEAD)
gcloud run deploy billiards-ball-detector \
  --source . \
  --region asia-northeast1 \
  --allow-unauthenticated \
  --set-env-vars "CORS_ORIGINS=https://7aota7-ai.github.io,GIT_SHA=${GIT_SHA}"
curl -s "$(gcloud run services describe billiards-ball-detector --region asia-northeast1 --format='value(status.url)')/health"
```

### それでも 0.1.4 の場合

```bash
gcloud config get-value project
gcloud run services describe billiards-ball-detector --region asia-northeast1 \
  --format='yaml(status.url,status.latestReadyRevisionName,metadata.generation)'
```

- **project** が以前デプロイしたプロジェクトと一致しているか
- **latestReadyRevisionName** がデプロイ直後に更新されているか

---

## GitHub Actions で Cloud Run デプロイ

`tools/ball_detector` を変更して `main` に push すると、Cloud Run へ自動デプロイされます（要 GitHub Secrets）。

| Secret | 内容 |
|--------|------|
| `GCP_SA_KEY` | デプロイ用サービスアカウント JSON（`roles/run.admin`, `cloudbuild.builds.builder`, `artifactregistry.writer`, `iam.serviceAccountUser`） |

手動実行: GitHub → Actions → **Deploy Ball Detector API** → Run workflow

デプロイ後 `/health` の `version` が `0.1.5` 以上なら反映完了です。

---

## Cloud Run 本番デプロイ（無料枠前提）

球検出 API を HTTPS で公開し、GitHub Pages（`https://7aota7-ai.github.io/billiards_flutter/`）から直接呼べます。  
**画像は保存せず JSON のみ返却**（メモリ上でデコード→検出→破棄）。

### 無料枠の目安（2025 時点・要 [公式料金表](https://cloud.google.com/run/pricing) 確認）

| サービス | 無料枠の目安 |
|----------|----------------|
| Cloud Run | 月 200 万リクエスト、一定の vCPU/メモリ秒 |
| Artifact Registry | 0.5 GB ストレージ |
| 課金アカウント | **有効化必須**（無料枠内なら実質 0 円のことが多い） |

個人利用・低トラフィックなら無料枠内に収まりやすい構成です。

### 変数（コマンド内で使う）

PowerShell / bash どちらでも、まずプロジェクト固有の値を設定してください。

```bash
# プロジェクト ID（英小文字・数字・ハイフン。例: billiards-detector-123）
export PROJECT_ID="YOUR_PROJECT_ID"

# リージョン（東京。無料枠はリージョン共通だがレイテンシ用）
export REGION="asia-northeast1"

# サービス名（URL の一部になる）
export SERVICE="billiards-ball-detector"

# Artifact Registry リポジトリ名
export REPO="ball-detector"

# GitHub Pages のオリジン（CORS 用。パスは含めない）
export CORS_ORIGIN="https://7aota7-ai.github.io"
```

Windows PowerShell の場合:

```powershell
$PROJECT_ID = "YOUR_PROJECT_ID"
$REGION = "asia-northeast1"
$SERVICE = "billiards-ball-detector"
$REPO = "ball-detector"
$CORS_ORIGIN = "https://7aota7-ai.github.io"
```

---

### ステップ 1: gcloud CLI のインストール

→ Google Cloud SDK を入れ、`gcloud` が使える状態にする。

- https://cloud.google.com/sdk/docs/install

```bash
gcloud version
```

---

### ステップ 2: GCP プロジェクト作成

→ 課金・API 有効化の単位になるプロジェクトを新規作成する。

```bash
gcloud projects create $PROJECT_ID --name="Billiards Ball Detector"
gcloud config set project $PROJECT_ID
```

既存プロジェクトを使う場合は `create` を飛ばし、`gcloud config set project` だけ実行。

---

### ステップ 3: 課金アカウントの紐付け

→ 無料枠を使うにも課金アカウントのリンクが必要（枠内は課金されないことが多い）。

コンソール: https://console.cloud.google.com/billing  
または:

```bash
# 利用可能な課金アカウント ID を確認
gcloud billing accounts list

# プロジェクトに紐付け（BILLING_ACCOUNT_ID を置換）
gcloud billing projects link $PROJECT_ID --billing-account=BILLING_ACCOUNT_ID
```

---

### ステップ 4: 必要 API の有効化

→ Cloud Run・コンテナビルド・Artifact Registry を使えるようにする。

```bash
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com
```

---

### ステップ 5: Artifact Registry リポジトリ作成

→ Docker イメージを置くプライベートレジストリを用意する。

```bash
gcloud artifacts repositories create $REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="Billiards ball detector API"
```

---

### ステップ 6: Docker 認証（初回のみ）

→ ローカル / Cloud Build から Artifact Registry へ push できるようにする。

```bash
gcloud auth configure-docker ${REGION}-docker.pkg.dev
```

---

### ステップ 7: イメージのビルド & push

→ `tools/ball_detector` から OpenCV + FastAPI イメージをビルドしてレジストリへ送る。

```bash
cd tools/ball_detector

export IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${SERVICE}:latest"

docker build -t $IMAGE .
docker push $IMAGE
```

（Cloud Build を使う場合）

```bash
gcloud builds submit --tag $IMAGE tools/ball_detector
```

---

### ステップ 8: Cloud Run へデプロイ

→ コンテナをサーバーレスで公開。環境変数で CORS・サイズ上限を設定する。

```bash
gcloud run deploy $SERVICE \
  --image=$IMAGE \
  --region=$REGION \
  --platform=managed \
  --allow-unauthenticated \
  --memory=512Mi \
  --cpu=1 \
  --timeout=60s \
  --max-instances=2 \
  --set-env-vars="CORS_ORIGINS=${CORS_ORIGIN},MAX_UPLOAD_BYTES=10485760,RATE_LIMIT_REQUESTS=30,RATE_LIMIT_WINDOW_SEC=60,LOG_DETECT_RESULTS=false"
```

| 環境変数 | 意味 |
|----------|------|
| `CORS_ORIGINS` | 許可オリジン（カンマ区切り）。本番は GitHub Pages のみ推奨 |
| `MAX_UPLOAD_BYTES` | 画像上限（既定 10MB） |
| `RATE_LIMIT_REQUESTS` | IP あたりの上限（インスタンス内・初期案 30/分） |
| `LOG_DETECT_RESULTS` | `false` = 検出 JSON をログに出さない |

デプロイ完了後、**サービス URL を控える**:

```bash
gcloud run services describe $SERVICE \
  --region=$REGION \
  --format='value(status.url)'
```

例: `https://billiards-ball-detector-xxxxx-an.a.run.app`

---

### ステップ 9: 動作確認

→ `/health` と `/detect` が動くか確認する。

**ヘルスチェック**

```bash
export API_URL=$(gcloud run services describe $SERVICE --region=$REGION --format='value(status.url)')

curl -s "$API_URL/health"
# => {"status":"ok","version":"0.1.5"}
```

**検出 API（サンプル画像）**

```bash
cd tools/ball_detector
DETECT_API_URL="$API_URL" python test_api.py samples/user_blue_table2.png
```

`ball_count=...` が表示されれば OK。

---

### ステップ 10: Flutter の baseUrl を本番 URL に差し替え

→ アプリが Cloud Run をデフォルトで叩くようにする。

`lib/services/detection_api_settings.dart` の `cloudRunUrl` をステップ 9 の URL に更新:

```dart
static const cloudRunUrl =
    'https://billiards-ball-detector-xxxxx-an.a.run.app';  // 実際の URL
```

GitHub Pages へ再デプロイ（`main` push で workflow が走る）。

**ローカル開発だけ HTTP API を使う場合:**

```bash
flutter run -d chrome --dart-define=DETECTION_API_URL=http://127.0.0.1:8765
```

---

### セキュリティ（最低限）

| 項目 | 実装 |
|------|------|
| 画像保存 | **しない**（メモリ処理のみ） |
| レスポンス | JSON のみ（座標・色ヒント） |
| CORS | GitHub Pages オリジンに制限（`CORS_ORIGINS`） |
| サイズ上限 | 10MB 超は HTTP 413 |
| ログ | ファイル書き込み廃止。Cloud Logging には `upload_bytes`・`ball_count`・処理時間のみ |
| レート制限 | インスタンス内 30 req/分/IP（`RateLimitMiddleware`）。スケールアウト時はインスタンスごとにカウントされるため、本格運用は [Cloud Armor](https://cloud.google.com/armor) や API ゲートウェイを検討 |
| 認証 | 現状は `--allow-unauthenticated`（公開 API）。悪用が気になる場合は IAP / API キー追加を検討 |

**ログの見方**

```bash
gcloud run services logs read $SERVICE --region=$REGION --limit=20
```

画像バイナリや全 JSON はログに出しません。

---

### 運用: コード更新の再デプロイ

→ 検出ロジック変更後、イメージを再ビルドして Cloud Run を更新する。

```bash
cd tools/ball_detector
export IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${SERVICE}:latest"

docker build -t $IMAGE .
docker push $IMAGE

gcloud run deploy $SERVICE --image=$IMAGE --region=$REGION
```

---

### トラブルシュート

| 症状 | 対処 |
|------|------|
| GitHub Pages から CORS エラー | `CORS_ORIGINS` に `https://7aota7-ai.github.io` が入っているか確認（末尾スラッシュなし） |
| 413 | 画像を圧縮するか `MAX_UPLOAD_BYTES` を一時的に引き上げ |
| 429 | レート制限。しばらく待つか `RATE_LIMIT_*` を調整 |
| コールドスタート遅延 | 初回 `/health` が 5〜10 秒かかることがある（Flutter は 10 秒タイムアウト） |
| 無料枠超過の心配 | Cloud Console → 請求 → 予算アラートを設定 |

---

## ローカル開発（従来どおり）
