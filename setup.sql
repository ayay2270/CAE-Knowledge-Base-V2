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
  images jsonb not null default '[]'::jsonb,
  views integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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

-- 4. 權限：只有登入的你本人能讀寫自己的資料
alter table public.entries enable row level security;

drop policy if exists "entries_select_own" on public.entries;
drop policy if exists "entries_insert_own" on public.entries;
drop policy if exists "entries_update_own" on public.entries;
drop policy if exists "entries_delete_own" on public.entries;

create policy "entries_select_own" on public.entries for select to authenticated using (user_id = auth.uid());
create policy "entries_insert_own" on public.entries for insert to authenticated with check (user_id = auth.uid());
create policy "entries_update_own" on public.entries for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "entries_delete_own" on public.entries for delete to authenticated using (user_id = auth.uid());

grant select, insert, update, delete on public.entries to authenticated;
grant execute on function public.increment_views(uuid) to authenticated;

-- 5. 圖片儲存空間（不公開，只有你本人能存取）
insert into storage.buckets (id, name, public)
values ('kb-images', 'kb-images', false)
on conflict (id) do nothing;

drop policy if exists "kb_images_select_own" on storage.objects;
drop policy if exists "kb_images_insert_own" on storage.objects;
drop policy if exists "kb_images_update_own" on storage.objects;
drop policy if exists "kb_images_delete_own" on storage.objects;

create policy "kb_images_select_own" on storage.objects for select to authenticated
  using (bucket_id = 'kb-images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "kb_images_insert_own" on storage.objects for insert to authenticated
  with check (bucket_id = 'kb-images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "kb_images_update_own" on storage.objects for update to authenticated
  using (bucket_id = 'kb-images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "kb_images_delete_own" on storage.objects for delete to authenticated
  using (bucket_id = 'kb-images' and (storage.foldername(name))[1] = auth.uid()::text);
