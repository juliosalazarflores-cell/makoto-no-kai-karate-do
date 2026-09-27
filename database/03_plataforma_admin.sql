-- ETAPA 3: CONTROL DE PLATAFORMA JSF & MAFIGO
-- Ejecutar una sola vez en Supabase SQL Editor.
-- No contiene contraseñas ni Secret Keys.

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.platform_admins enable row level security;

create or replace function public.is_platform_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (select 1 from public.platform_admins where user_id = auth.uid());
$$;

revoke all on function public.is_platform_admin() from public;
grant execute on function public.is_platform_admin() to authenticated;

drop policy if exists "platform admins read own record" on public.platform_admins;
create policy "platform admins read own record"
on public.platform_admins for select to authenticated
using (user_id = auth.uid());

-- Permisos de plataforma sobre organizaciones.
drop policy if exists "platform admins read organizations" on public.organizations;
create policy "platform admins read organizations"
on public.organizations for select to authenticated
using (public.is_platform_admin() or public.is_org_member(id));

drop policy if exists "platform admins insert organizations" on public.organizations;
create policy "platform admins insert organizations"
on public.organizations for insert to authenticated
with check (public.is_platform_admin());

drop policy if exists "platform admins update organizations" on public.organizations;
create policy "platform admins update organizations"
on public.organizations for update to authenticated
using (public.is_platform_admin() or public.is_org_admin(id))
with check (public.is_platform_admin() or public.is_org_admin(id));

-- Administración de miembros de organizaciones.
drop policy if exists "platform admins read all members" on public.organization_members;
create policy "platform admins read all members"
on public.organization_members for select to authenticated
using (public.is_platform_admin() or user_id = auth.uid() or public.is_org_admin(organization_id));

-- Registro de auditoría de acciones de plataforma.
create table if not exists public.platform_audit_log (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid not null references auth.users(id) on delete cascade,
  action text not null,
  organization_id uuid references public.organizations(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.platform_audit_log enable row level security;
drop policy if exists "platform admins manage audit log" on public.platform_audit_log;
create policy "platform admins manage audit log"
on public.platform_audit_log for all to authenticated
using (public.is_platform_admin())
with check (public.is_platform_admin() and admin_user_id = auth.uid());

-- IMPORTANTE: después de crear la tabla, agrega al usuario administrador de JSF & MAFIGO:
-- insert into public.platform_admins(user_id) values ('UUID_DEL_USUARIO_ADMIN');
-- on conflict (user_id) do nothing;
