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

### B. GitHub Pages（讓網站可以用網址打開）

1. 到 repo 頁面 https://github.com/ayay2270/CAE-Knowledge-Base-V2 ，點上方分頁列最右邊的 **Settings**（齒輪圖示）。
2. 左側選單往下找到 **Pages**（在「Code and automation」那一區）。
3. 在 **Build and deployment** 底下：
   - **Source** 選 **Deploy from a branch**
   - **Branch** 的第一個下拉選 **main**，第二個下拉選 **/ (root)**
   - 按 **Save**
4. 等 1～3 分鐘後重新整理 Pages 頁面，最上方會出現 **Your site is live at …** 和 **Visit site** 按鈕。

網站網址：**https://ayay2270.github.io/CAE-Knowledge-Base-V2/**

（選用）回到 repo 首頁，右側 **About** 旁邊的齒輪 → 勾選 **Use your GitHub Pages website** → Save，之後 repo 首頁就會直接顯示網站連結。

### C. 第一次開啟

打開上面的網站網址 → 貼上 Project URL 和 publishable key → 用 A-3 建立的帳號登入。

## 之後更新網站

1. 在 repo 首頁點 **Add file → Upload files**。
2. 把新版 `index.html` 拖進去（檔名必須是 `index.html`，如果下載後變成 `index_1.html` 要先改回來）。
3. 按 **Commit changes**。同名檔案會自動覆蓋舊的。
4. 等 1～2 分鐘，重新整理網站。資料存在 Supabase，不會受影響。

## 常見問題

- **打不開、顯示連不到 Supabase**：免費方案的專案一段時間沒使用會被暫停。登入 Supabase，在專案頁按 **Restore / Resume**，資料不會不見。
- **換了一台電腦**：第一次打開一樣要貼一次 URL 和 key。
- **備份**：右上角人像選單 → 匯出備份（JSON）。
