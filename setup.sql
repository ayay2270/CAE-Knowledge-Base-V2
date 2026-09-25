-- CAE Knowledge Base：Supabase 初始設定
-- 使用方式：整份複製，貼到 Supabase 的 SQL Editor，按 Run。重複執行也沒關係。

-- 1. 知識資料表
create table if not exists public.entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  category text not null,
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

-- 6. 共用軟體分類。key 是穩定內部代碼，label 是顯示名稱。
--    一般介面只把 is_active 設成 false，不實體刪除，既有知識的 category 不會被改寫。
create table if not exists public.software_categories (
  key text primary key,
  label text not null,
  parent_key text null,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists software_categories_touch on public.software_categories;
create trigger software_categories_touch before update on public.software_categories
for each row execute function public.touch_updated_at();

-- 預設階層。已存在的 key 不覆寫，避免重跑時蓋掉改過的名稱。
insert into public.software_categories (key, label, parent_key, is_active, sort_order)
values
  ('hm', 'HyperMesh', null, true, 0),
  ('optistruct', 'OptiStruct', 'hm', true, 20),
  ('lsdyna', 'LS-DYNA', null, true, 30)
on conflict (key) do nothing;

-- 對不上 software_categories 就停止。此時舊的 CHECK 還在，外鍵也不會被加上。
-- 不改寫既有的 category 值。
do $$
declare
  missing text;
begin
  select string_agg(distinct e.category, ', ' order by e.category)
    into missing
  from public.entries e
  where not exists (
    select 1 from public.software_categories s where s.key = e.category
  );

  if missing is not null then
    raise exception
      'Stopped before dropping the category CHECK and before adding the foreign key. entries.category values missing from software_categories: %. Nothing was rewritten.',
      missing;
  end if;
end $$;

-- 只移除「單一欄位 public.entries.category」上、定義完全等於舊三值集合的 CHECK。
-- 不因定義裡出現 hypermesh 就刪除。名稱不同也只在定義吻合時才刪。
-- 若 category 上有別種 CHECK，停止且不刪除。
-- PostgreSQL 會把
--   check (category in ('hypermesh', 'optistruct', 'lsdyna'))
-- 存成：
--   CHECK ((category = ANY (ARRAY['hypermesh'::text, 'optistruct'::text, 'lsdyna'::text])))
do $$
declare
  category_attnum smallint;
  old_shape text := 'CHECK ((category = ANY (ARRAY[''hypermesh''::text, ''optistruct''::text, ''lsdyna''::text])))';
  r record;
begin
  select a.attnum
    into category_attnum
  from pg_attribute a
  where a.attrelid = 'public.entries'::regclass
    and a.attname = 'category'
    and not a.attisdropped;

  if category_attnum is null then
    raise exception 'Stopped. public.entries.category does not exist.';
  end if;

  for r in
    select c.conname, pg_get_constraintdef(c.oid) as definition
    from pg_constraint c
    where c.conrelid = 'public.entries'::regclass
      and c.contype = 'c'
      and c.conkey = array[category_attnum]::smallint[]
  loop
    if regexp_replace(r.definition, '\s+', ' ', 'g') is distinct from old_shape then
      raise exception
        'Stopped. entries.category has a CHECK that is not the old three-value set, so it was not dropped. Constraint: %, definition: %',
        r.conname, r.definition;
    end if;

    execute format('alter table public.entries drop constraint %I', r.conname);
  end loop;
end $$;

-- 看欄位與參照目標，不看約束名稱。
-- 已有同等外鍵（RESTRICT 或 NO ACTION）就不重複加。
-- 同一欄若是別種外鍵：停止，不改它。
do $$
declare
  category_attnum smallint;
  target_attnum smallint;
  r record;
  found_equivalent boolean := false;
begin
  select a.attnum into category_attnum
  from pg_attribute a
  where a.attrelid = 'public.entries'::regclass
    and a.attname = 'category' and not a.attisdropped;

  select a.attnum into target_attnum
  from pg_attribute a
  where a.attrelid = 'public.software_categories'::regclass
    and a.attname = 'key' and not a.attisdropped;

  for r in
    select c.conname, c.confrelid, c.confkey, c.confdeltype
    from pg_constraint c
    where c.conrelid = 'public.entries'::regclass
      and c.contype = 'f'
      and c.conkey = array[category_attnum]::smallint[]
  loop
    if r.confrelid = 'public.software_categories'::regclass
       and r.confkey = array[target_attnum]::smallint[]
       and r.confdeltype in ('a', 'r') then
      found_equivalent := true;
    else
      raise exception
        'Stopped. entries.category already has a different foreign key (%). It was not changed.',
        r.conname;
    end if;
  end loop;

  if not found_equivalent then
    alter table public.entries
      add constraint entries_category_fkey
      foreign key (category) references public.software_categories (key)
      on delete restrict;
  end if;
end $$;

do $$
declare
  parent_attnum smallint;
  key_attnum smallint;
  r record;
  found_equivalent boolean := false;
begin
  select a.attnum into parent_attnum
  from pg_attribute a
  where a.attrelid = 'public.software_categories'::regclass
    and a.attname = 'parent_key' and not a.attisdropped;

  select a.attnum into key_attnum
  from pg_attribute a
  where a.attrelid = 'public.software_categories'::regclass
    and a.attname = 'key' and not a.attisdropped;

  for r in
    select c.conname, c.confrelid, c.confkey, c.confdeltype
    from pg_constraint c
    where c.conrelid = 'public.software_categories'::regclass
      and c.contype = 'f'
      and c.conkey = array[parent_attnum]::smallint[]
  loop
    if r.confrelid = 'public.software_categories'::regclass
       and r.confkey = array[key_attnum]::smallint[]
       and r.confdeltype in ('a', 'r') then
      found_equivalent := true;
    else
      raise exception
        'Stopped. software_categories.parent_key already has a different foreign key (%). It was not changed.',
        r.conname;
    end if;
  end loop;

  if not found_equivalent then
    alter table public.software_categories
      add constraint software_categories_parent_key_fkey
      foreign key (parent_key) references public.software_categories (key)
      on delete restrict;
  end if;
end $$;

alter table public.software_categories enable row level security;

drop policy if exists "software_categories_public_read" on public.software_categories;
drop policy if exists "software_categories_authenticated_insert" on public.software_categories;
drop policy if exists "software_categories_authenticated_update" on public.software_categories;

-- 匿名只讀使用中的分類。登入者可讀全部（含已隱藏），才能顯示既有知識的名稱。
create policy "software_categories_public_read" on public.software_categories
  for select to anon, authenticated
  using (is_active = true or auth.role() = 'authenticated');
create policy "software_categories_authenticated_insert" on public.software_categories
  for insert to authenticated with check (true);
create policy "software_categories_authenticated_update" on public.software_categories
  for update to authenticated using (true) with check (true);

revoke all on public.software_categories from public, anon, authenticated;
grant select on public.software_categories to anon, authenticated;
grant insert, update on public.software_categories to authenticated;
