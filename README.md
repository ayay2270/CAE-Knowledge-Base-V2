# CAE Knowledge Base

個人 CAE 除錯知識庫。網頁放在 GitHub Pages，資料和圖片存在 Supabase。

## 檔案說明

- `index.html`：網站本體
- `setup.sql`：Supabase 初始設定（只需要執行一次）

## 第一次設定

### A. Supabase

1. 到 supabase.com 註冊（可以直接用 GitHub 帳號登入），按 **New project**。名稱自訂，Region 選 **Northeast Asia (Tokyo)**，資料庫密碼記下來（平常用不到）。
2. 專案建好後，左側選單點 **SQL Editor** → 新增一個 query，把 `setup.sql` 全部內容貼上 → 按 **Run**，看到 Success 就完成。
3. 左側 **Authentication → Users → Add user → Create new user**，填你的 Email 和密碼，勾選 **Auto Confirm User**，建立。
4. **Authentication** 裡找到 Sign In / Providers 的設定，把 **Allow new users to sign up** 關掉並儲存，這樣別人就不能註冊。
5. 到 **Project Settings → API Keys**（或專案首頁的 **Connect** 按鈕），複製 **Project URL** 和 **publishable key**（舊專案叫 anon key）。
   ⚠️ 不要使用 secret key 或 service_role key。

### B. GitHub Pages

1. GitHub 右上角 **+ → New repository**，名稱例如 `cae-kb`，選 **Public**，按 Create。
2. 在新 repo 頁面點 **uploading an existing file**，把 `index.html`、`setup.sql`、`README.md` 拖進去 → **Commit changes**。
3. **Settings → Pages**，Source 選 **Deploy from a branch**，Branch 選 **main**、資料夾 **/(root)** → Save。
4. 等 1～2 分鐘，網站會出現在 `https://你的帳號.github.io/cae-kb/`。

### C. 第一次開啟

打開網站 → 貼上 Project URL 和 publishable key → 用步驟 A-3 的帳號登入。

## 之後更新網站

我（Claude）給你新版 `index.html` 時，到 repo 點 `index.html` → 右上角 **⋯ → Delete file** 或直接用 **Add file → Upload files** 上傳同名檔案覆蓋 → Commit。1～2 分鐘後重新整理網站即可。資料不會受影響。

## 常見問題

- **打不開、顯示連不到 Supabase**：免費方案的專案一段時間沒使用會被暫停。登入 Supabase，在專案頁按 **Restore / Resume**，資料不會不見。
- **換了一台電腦**：第一次打開一樣要貼一次 URL 和 key。
- **備份**：右上角人像選單 → 匯出備份（JSON）。
