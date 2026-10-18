# 駱駝教師生涯導航｜Supabase 修正版

ZIP 內含四個檔案：
- `schema.sql`：Supabase / PostgreSQL 資料庫初始結構
- `index.html`：可在 Safari、Chrome、Edge 開啟的互動式網站原型
- `能力模型與系統設定.json`：能力模型草案、評分規則、角色與版本設定
- `README.md`：本說明文件

## 本次 SQL 修正
原錯誤 `ERROR: 42710: type "app_role" already exists` 是因為專案中已存在同名 PostgreSQL type。新版 SQL **不再建立 `app_role`**，改用 `text` 欄位搭配 `CHECK (role in ('teacher','admin'))`，並對資料表、索引使用 `IF NOT EXISTS`。職位初始資料使用 `ON CONFLICT`。

## 如何使用
1. 下載並解壓縮 ZIP。
2. 在 Supabase Dashboard → SQL Editor 開啟 `schema.sql`，建議先在測試專案執行。
3. `index.html` 可直接用瀏覽器開啟；不需要安裝。
4. JSON 是設定文件，不要貼進 SQL Editor。

## 重要限制與安全事項
- 此網站是前端互動原型，不是已部署的正式服務。
- HTML 尚未連接 Supabase，沒有真正的 Email/密碼登入、Google OAuth、後端 API 或跨裝置同步；資料目前存在瀏覽器 localStorage。
- SQL 會啟用部分個人資料表的 RLS，但刻意不建立 policies。完成並測試政策前，透過 Supabase client 的一般請求會被拒絕。請依正式權限需求建立逐表 policies。
- 教師應只能讀寫自己的個人評估、計畫與週進度；管理員管理模型並查看去識別化彙整統計，預設不得查看個別評估詳情。
- 絕不可將 Supabase `service_role` key 放在前端。
- 能力模型、目標等級、權重均為討論草案，不代表正式評量標準。
- 薪資只記錄薪級／職級代碼，不記錄實際薪資。
- `overall_score` 公式尚未定義，因此資料欄位保留但不自動計算。

## 若仍有 SQL 錯誤
請提供完整錯誤訊息與行號。若專案中已有舊版同名資料表，`IF NOT EXISTS` 不會自動遷移其欄位；需要另寫 migration 以符合現有結構。
