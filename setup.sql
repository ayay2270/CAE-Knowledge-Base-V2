-- CAE Knowledge Base：Supabase 初始設定
-- 使用方式：整份複製，貼到 Supabase 的 SQL Editor，按 Run。重複執行也沒關係。

-- 1. 知識資料表
create table if not exists public.entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  category text not null check (category in ('hypermesh', 'optistruct', 'lsdyna')),
  tags text[] not null default '{}',
  symptom text not null default '',
  root_cause text not null default '',
  solution text not null default '',
  failed_attempts text[] not null default '{}',
  notes text not null default '',
  reference_source text not null default '',
  images jsonb not null default '[]'::jsonb,
  views integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 1b. 既有資料庫補上「參考來源」（重複執行也沒關係；不改 views、不刪資料）
alter table public.entries
  add column if not exists reference_source text not null default '';

-- 2. 內容有修改時才更新「更新時間」（瀏覽次數變動不算）
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  if (to_jsonb(new) - 'views' - 'updated_at') is distinct from (to_jsonb(old) - 'views' - 'updated_at') then
    new.updated_at = now();
  end if;
  return new;
end $$;

drop trigger if exists entries_touch on public.entries;
create trigger entries_touch before update on public.entries
for each row execute function public.touch_updated_at();

-- 3. 瀏覽次數 +1
create or replace function public.increment_views(entry_id uuid)
returns void language sql security invoker as $$
  update public.entries set views = views + 1 where id = entry_id;
$$;

-- 4. 權限：匿名與登入者都可讀；新增／修改／刪除只給 authenticated
--    條件是 true，不是 user_id = auth.uid()
--    increment_views 只給 authenticated，匿名瀏覽不會加瀏覽次數
alter table public.entries enable row level security;

drop policy if exists "entries_select_own" on public.entries;
drop policy if exists "entries_select_public" on public.entries;
drop policy if exists "entries_insert_own" on public.entries;
drop policy if exists "entries_update_own" on public.entries;
drop policy if exists "entries_delete_own" on public.entries;
drop policy if exists "entries_public_read" on public.entries;
drop policy if exists "entries_authenticated_insert" on public.entries;
drop policy if exists "entries_authenticated_update" on public.entries;
drop policy if exists "entries_authenticated_delete" on public.entries;

create policy "entries_public_read" on public.entries
  for select to anon, authenticated using (true);
create policy "entries_authenticated_insert" on public.entries
  for insert to authenticated with check (true);
create policy "entries_authenticated_update" on public.entries
  for update to authenticated using (true) with check (true);
create policy "entries_authenticated_delete" on public.entries
  for delete to authenticated using (true);

grant select on public.entries to anon;
grant select, insert, update, delete on public.entries to authenticated;
revoke execute on function public.increment_views(uuid) from public, anon;
grant execute on function public.increment_views(uuid) to authenticated;

-- 5. 圖片：bucket 不公開。匿名與登入者可讀 kb-images；上傳／修改／刪除只給 authenticated
--    條件只看 bucket_id，不是資料夾擁有者
insert into storage.buckets (id, name, public)
values ('kb-images', 'kb-images', false)
on conflict (id) do nothing;

drop policy if exists "kb_images_select_own" on storage.objects;
drop policy if exists "kb_images_select_public" on storage.objects;
drop policy if exists "kb_images_insert_own" on storage.objects;
drop policy if exists "kb_images_update_own" on storage.objects;
drop policy if exists "kb_images_delete_own" on storage.objects;
drop policy if exists "kb_images_public_read" on storage.objects;
drop policy if exists "kb_images_authenticated_insert" on storage.objects;
drop policy if exists "kb_images_authenticated_update" on storage.objects;
drop policy if exists "kb_images_authenticated_delete" on storage.objects;

create policy "kb_images_public_read" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'kb-images');
create policy "kb_images_authenticated_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'kb-images');
create policy "kb_images_authenticated_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'kb-images')
  with check (bucket_id = 'kb-images');
create policy "kb_images_authenticated_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'kb-images');
