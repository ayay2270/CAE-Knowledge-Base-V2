-- CAE Knowledge Base：既有資料庫升級到共用 software_categories
-- 只給「已經在跑、category 仍受 hypermesh/optistruct/lsdyna 限制」的資料庫。
-- 不要拿整份 setup.sql 來做這次升級。
-- 這份腳本不會改 entries 的資料、不會刪 category 欄、不會動 entries / kb-images 的政策。
-- 可重複執行。請先單獨跑下面的「執行前查詢」。那些查詢不在交易裡。
-- 確認結果後，從 BEGIN 跑到 COMMIT。任一 DO 區塊拋出例外，或結構／RLS／外鍵失敗，
-- 整段交易會回滾，不會留下做一半的結構。這裡沒有吞掉錯誤的 EXCEPTION 處理。
-- 本檔不會自動執行。

-- ============================================================
-- 執行前查詢（只讀，在 BEGIN 之外，請先單獨跑）
-- ============================================================
-- 1. 目前 entries.category 有哪些值
-- select category, count(*)
-- from public.entries
-- group by category
-- order by category;
--
-- 2. entries 上現有的 CHECK
-- select c.conname,
--        pg_get_constraintdef(c.oid) as definition,
--        a.attname as column_name,
--        cardinality(c.conkey) as column_count
-- from pg_constraint c
-- left join pg_attribute a
--   on a.attrelid = c.conrelid
--  and a.attnum = c.conkey[1]
--  and cardinality(c.conkey) = 1
-- where c.conrelid = 'public.entries'::regclass
--   and c.contype = 'c'
-- order by c.conname;
--
-- 3. software_categories 是否已存在
-- select to_regclass('public.software_categories') as software_categories;
--
-- 4. entries.category 的外鍵是否已存在
-- select c.conname, pg_get_constraintdef(c.oid) as definition
-- from pg_constraint c
-- where c.conrelid = 'public.entries'::regclass
--   and c.contype = 'f'
--   and c.conname = 'entries_category_fkey';

-- 預期 category 只有 hypermesh、optistruct、lsdyna。
-- 若有別的值，交易會在任何結構變更之前停止，而且不會改寫那些值。

begin;

do $$
declare
  unexpected text;
begin
  select string_agg(distinct category, ', ' order by category)
    into unexpected
  from public.entries
  where category is distinct from 'hypermesh'
    and category is distinct from 'optistruct'
    and category is distinct from 'lsdyna';

  if unexpected is not null then
    raise exception
      'Migration stopped before any change. Unexpected public.entries.category values: %. These values were not rewritten.',
      unexpected;
  end if;
end $$;

do $$
begin
  if to_regprocedure('public.touch_updated_at()') is null then
    raise exception
      'Migration stopped. public.touch_updated_at() does not exist, so software_categories cannot reuse it.';
  end if;
end $$;

create table if not exists public.software_categories (
  key text primary key,
  label text not null,
  parent_key text null,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.software_categories (key, label, parent_key, is_active, sort_order)
values
  ('hm', 'HyperMesh', null, true, 0),
  ('optistruct', 'OptiStruct', 'hm', true, 20),
  ('lsdyna', 'LS-DYNA', null, true, 30)
on conflict (key) do nothing;

-- 外鍵之前再確認一次：每個既有 category 都已經是 software_categories.key。
-- 對不上就停止。此時舊的 CHECK 還在，外鍵也不會被加上。
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
      'Migration stopped before dropping the category CHECK and before adding the foreign key. entries.category values missing from software_categories: %. Nothing was rewritten.',
      missing;
  end if;
end $$;

-- 只移除「單一欄位 public.entries.category」上、定義完全等於舊三值集合的 CHECK。
-- 不因定義裡出現 hypermesh 就刪除。名稱不同也只在定義吻合時才刪。
-- 若 category 上有別種 CHECK，停止且不刪除。
-- PostgreSQL 會把
--   check (category in ('hypermesh', 'optistruct', 'lsdyna'))
-- 存成下面這個正規化定義（空白忽略後比對）：
--   CHECK ((category = ANY (ARRAY['hypermesh'::text, 'optistruct'::text, 'lsdyna'::text])))
do $$
declare
  category_attnum smallint;
  old_shape text := 'CHECK ((category = ANY (ARRAY[''hypermesh''::text, ''optistruct''::text, ''lsdyna''::text])))';
  r record;
  dropped int := 0;
begin
  select a.attnum
    into category_attnum
  from pg_attribute a
  where a.attrelid = 'public.entries'::regclass
    and a.attname = 'category'
    and not a.attisdropped;

  if category_attnum is null then
    raise exception 'Migration stopped. public.entries.category does not exist.';
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
        'Migration stopped. entries.category has a CHECK that is not the old three-value set, so it was not dropped. Constraint: %, definition: %',
        r.conname, r.definition;
    end if;

    execute format('alter table public.entries drop constraint %I', r.conname);
    dropped := dropped + 1;
  end loop;

  raise notice 'Old entries.category CHECK constraints dropped: %', dropped;
end $$;

-- 看欄位與參照目標，不看約束名稱。
-- 已有 entries.category → software_categories.key，且刪除動作是 RESTRICT 或 NO ACTION：不重複加。
-- 同一欄若指向別處，或是 CASCADE / SET NULL / SET DEFAULT：停止，不改既有外鍵。
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
        'Migration stopped. entries.category already has a different foreign key (%). It was not changed.',
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

-- parent_key 的自我參照外鍵放在種子之後再加，避免建表當下的順序問題。
-- 判斷方式與上面相同。ON DELETE RESTRICT：不能因為刪上層而連帶刪子分類。
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
        'Migration stopped. software_categories.parent_key already has a different foreign key (%). It was not changed.',
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

drop trigger if exists software_categories_touch on public.software_categories;
create trigger software_categories_touch
  before update on public.software_categories
  for each row execute function public.touch_updated_at();

alter table public.software_categories enable row level security;

drop policy if exists "software_categories_public_read" on public.software_categories;
drop policy if exists "software_categories_authenticated_insert" on public.software_categories;
drop policy if exists "software_categories_authenticated_update" on public.software_categories;

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

commit;
