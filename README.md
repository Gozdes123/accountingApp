# 個人記帳與投資追蹤系統 (Personal Accounting & Investment Tracker)

這是一個基於 **Vue 3 (Composition API / `<script setup>`)** 與 **Vite** 開發的個人資產記帳與投資報酬率（ROI）追蹤單頁應用程式 (SPA)，後端採用 **Supabase** 進行雲端同步，並具備本機快取優先 (SWR) 的秒開功能。

---

## 🌟 核心功能模組

### 1. 資產與負債管理
- **資產帳戶**：支援流動資金（銀行、現金、電子錢包）、投資帳戶、固定資產、應收款項。
- **負債帳戶**：支援信用卡、貸款、應付款項。
- **自動記帳/轉帳**：支援週期性自動生成收支紀錄。
- **每日資產快照**：自動保存每日淨資產歷史，用於繪製長期趨勢圖。

### 2. 投資標的管理
- 支援台股、美股、加密貨幣、基金等多種資產類別。
- 記錄持有數量 (`quantity`)、平均成本 (`average_cost` / `buy_price`)、買入日期 (`buy_date`) 以及自訂群組關係。
- 支援與實體資金帳戶的**扣款帳戶連動**（購置投資時自動扣減相應銀行餘額）。

### 3. Yahoo Finance 即時股價與匯率整合
- 使用 **Vercel Serverless Function (`api/yahoo-proxy.js`)** 作為 CORS 代理，即時獲取 Yahoo Finance 的標的報價與歷史走勢。
- 若伺服器端代理失效，自動嘗試多種免費 CORS 代理作為 Fallback，確保線上運作不中斷。
- 自動抓取即時 USD/TWD 匯率轉換美股與加密貨幣市值。

### 4. 數據視覺化 (Chart.js)
- **淨資產與負債趨勢圖**：展示資產累積歷程。
- **流動資金與投資分布圖**：以甜甜圈圖/圓餅圖呈現資產配置比例。
- **歷史投資報酬率 (ROI) 走勢折線圖**：
  - 長期 ROI 的走勢統計，支援「整體」及「自訂群組」複數折線。
  - **LOCF (Last Observation Carried Forward) 演算法**：解決不同交易所/市場開休市時間不一致導致特定日期資料缺失的問題，使用最新已知價格向前填充。
  - **買入日限制 (Pre-Purchase Exclusion)**：每筆投資只在其 `buy_date` 起算，買入前的歷史時間不計入成本與市值，徹底消除「未買入期」產生的暴跌 -50% 異常數值。
  - **前端空白裁切**：圖表自動從第一筆交易發生的日期開始繪製。

### 5. 自訂群組與批次操作
- 支援對投資標的與帳戶自訂群組（例如：「台股」、「美股」、「高股息」）。
- 主頁趨勢圖上方提供精美 **玻璃擬態橫向滾動膠囊 (Glassmorphism Scrollable Chips)**，整合群組顏色、名稱及當前 ROI 漲跌幅百分比。
- 具備 **複選批次加入群組功能**：利用滾動 Checkbox 列表與 `Promise.all` 併發寫入，快速調整標的分類。

---

## 📁 專案架構與關鍵檔案

- **[src/components/Dashboard.vue](file:///e:/code/accounting_app/src/components/Dashboard.vue)**: 核心 SPA 元件，承載 90% 的前端邏輯（狀態、圖表配置、Supabase CRUD、Yahoo 報價拉取）。
- **[api/yahoo-proxy.js](file:///e:/code/accounting_app/api/yahoo-proxy.js)**: Vercel 運行的後端 API 代理，處理 Yahoo Finance API 的跨域請求。
- **[src/lib/supabaseClient.js](file:///e:/code/accounting_app/src/lib/supabaseClient.js)**: Supabase 初始化客戶端。
- **[supabase_setup.sql](file:///e:/code/accounting_app/supabase_setup.sql)**: 包含 Supabase 資料表（`accounts`, `investments`, `net_worth_history`, `income_expense`）的資料表綱要。

---

## 💾 資料模型與快取機制 (SWR)

本專案實施 **Stale-While-Revalidate (SWR)** 機制：
1. **本機渲染優先**：頁面加載時先讀取 `localStorage` 中的 `local_accounts` 與 `local_investments` 快速呈現在畫面上。
2. **背景同步**：在背景異步向 Supabase 查詢最新數據，並寫回 `localStorage` 與網頁狀態。
3. **防搶寫安全網 (Safety Net)**：若 Supabase 還沒完成本地新增群組的更新，`fetchAllData` 重新拉取時會自動將本機 `localStorage` 的 `custom_group` 屬性 merge 回來，避免 race condition 導致群組設定遺失。

---

## 💡 AI 模型開發注意事項 (For Future LLMs / Code Agents)

如果你是後續接手的 Gemini、Claude、GPT 等 AI 編碼助理，請嚴格遵守以下系統設計約定：

1. **避免重置 `custom_group`**
   - 在 `selectSubtype` 函數（彈出視窗切換資產類型）中，**必須**繼承並保留當前選取的群組值 (`newAsset.value.custom_group = activeCustomGroup.value || ''`)，不可將其重置為空字串 `''`。
   - 同步 Supabase 資料時，若 DB 返回的群組欄位為空，必須與本機 `localStorage` 進行 merge 合併（參考 `fetchAllData` 內的 `localInvMap` 邏輯）。

2. **Chart.js 全域填充外掛 (Filler Plugin)**
   - 本專案在全域註冊了 Chart.js 的 `Filler` 外掛，因此在配置折線圖時，若不需要填滿下方區塊，必須在 datasets 設定 `fill: false`，並在 options 的全域層級配置 `elements.line.fill: false`，否則會跑出難看的背景填滿色。

3. **DOM 排版與彈出視窗 Flexbox**
   - Checkbox 列表排版應注意避免使用易被擠壓的 `flex: 1` 且無 `min-width` 的 white-space 截斷。應使用 `div` 作為卡片外包裝以隔離樣式污染，並讓內部的 `<label>` 控制文字對齊，確保文字正常顯現。

4. **編碼安全性 (UTF-8)**
   - 修改 `Dashboard.vue` 時，請確保檔案編碼儲存為 **UTF-8 (without BOM)**，以避免代碼中的 Emoji 圖示（如 📈, 🏦）在瀏覽器渲染或某些終端編譯下變成亂碼或消失。
