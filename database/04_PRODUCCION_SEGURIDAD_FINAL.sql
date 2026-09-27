-- JSF & MAFIGO SPORT SYSTEMS
-- PRODUCCION DEFINITIVA - SEGURIDAD MULTI-ORGANIZACION
-- Version autocontenida: requiere las tablas base de Stage 2 (organizations, organization_members y modulos operativos).
-- No contiene Secret Keys.

create extension if not exists pgcrypto;

-- ============================================================
-- 0) PREPARACION AUTOCONTENIDA
-- ============================================================
-- Esta version no depende de que 02_expediente_alumnos.sql o 03_plataforma_admin.sql
-- hayan sido ejecutados previamente. Crea solo lo que falte.

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.platform_admins enable row level security;

create table if not exists public.platform_audit_log (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid not null references auth.users(id) on delete cascade,
  action text not null,
  organization_id uuid references public.organizations(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.platform_audit_log enable row level security;

-- Extensiones del expediente de alumnos: solo si existe la tabla base students.
do $$
begin
  if to_regclass('public.students') is not null then
    alter table public.students
      add column if not exists email text,
      add column if not exists birth_date date,
      add column if not exists join_date date,
      add column if not exists guardian text,
      add column if not exists emergency_phone text,
      add column if not exists group_name text,
      add column if not exists id_number text,
      add column if not exists address text,
      add column if not exists notes text;
  end if;
end $$;

-- Crea las tablas del expediente solo si students ya existe.
do $$
begin
  if to_regclass('public.students') is not null then
    execute $sql$
      create table if not exists public.student_profiles (
        id uuid primary key default gen_random_uuid(),
        organization_id uuid not null references public.organizations(id) on delete cascade,
        student_id uuid not null unique references public.students(id) on delete cascade,
        photo_url text, grade_history text, medical_notes text, allergies text,
        emergency_contact_name text, emergency_contact_phone text, insurance_info text,
        consent_notes text, created_at timestamptz not null default now(),
        updated_at timestamptz not null default now()
      );
      create table if not exists public.student_attendance_records (
        id uuid primary key default gen_random_uuid(),
        organization_id uuid not null references public.organizations(id) on delete cascade,
        student_id uuid not null references public.students(id) on delete cascade,
        attendance_date date not null, status text not null default 'Presente',
        notes text, created_at timestamptz not null default now()
      );
      create table if not exists public.student_payment_records (
        id uuid primary key default gen_random_uuid(),
        organization_id uuid not null references public.organizations(id) on delete cascade,
        student_id uuid not null references public.students(id) on delete cascade,
        payment_date date not null, amount numeric(12,2) not null default 0,
        concept text, status text not null default 'Pagado', notes text,
        created_at timestamptz not null default now()
      );
      create table if not exists public.student_exam_records (
        id uuid primary key default gen_random_uuid(),
        organization_id uuid not null references public.organizations(id) on delete cascade,
        student_id uuid not null references public.students(id) on delete cascade,
        exam_date date not null, title text, grade text, result text,
        cost numeric(12,2) default 0, notes text, created_at timestamptz not null default now()
      );
      create table if not exists public.student_competition_records (
        id uuid primary key default gen_random_uuid(),
        organization_id uuid not null references public.organizations(id) on delete cascade,
        student_id uuid not null references public.students(id) on delete cascade,
        event_date date not null, name text, category text, result text, notes text,
        created_at timestamptz not null default now()
      );
    $sql$;
  end if;
end $$;

-- ============================================================
-- 0) LIMPIEZA PREVIA DE POLITICAS Y FUNCIONES EXISTENTES
-- ============================================================
do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname='public'
      and tablename in (
        'organizations','organization_members','students','instructors','attendance','payments',
        'exams','competitions','notices','credentials','technical_programs',
        'student_profiles','student_attendance_records','student_payment_records',
        'student_exam_records','student_competition_records','platform_audit_log'
      )
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- PostgreSQL no permite cambiar el nombre de un parámetro de entrada con
-- CREATE OR REPLACE FUNCTION. Se eliminan primero las funciones de autorización.
drop function if exists public.is_org_member(uuid);
drop function if exists public.is_org_admin(uuid);
drop function if exists public.is_org_editor(uuid);

-- ============================================================
-- 1) FUNCIONES DE AUTORIZACION
-- ============================================================
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.platform_admins pa
    where pa.user_id = auth.uid()
  );
$$;

revoke all on function public.is_platform_admin() from public;
grant execute on function public.is_platform_admin() to authenticated;


create or replace function public.is_org_member(org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.organization_members om
    join public.organizations o on o.id = om.organization_id
    where om.organization_id = org_id
      and om.user_id = auth.uid()
      and coalesce(o.status, 'active') = 'active'
      and (o.expires_at is null or o.expires_at >= current_date)
  );
$$;

create or replace function public.is_org_admin(org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.organization_members om
    join public.organizations o on o.id = om.organization_id
    where om.organization_id = org_id
      and om.user_id = auth.uid()
      and om.role in ('owner','admin')
      and coalesce(o.status, 'active') = 'active'
      and (o.expires_at is null or o.expires_at >= current_date)
  );
$$;

create or replace function public.is_org_editor(org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.organization_members om
    join public.organizations o on o.id = om.organization_id
    where om.organization_id = org_id
      and om.user_id = auth.uid()
      and om.role in ('owner','admin','instructor')
      and coalesce(o.status, 'active') = 'active'
      and (o.expires_at is null or o.expires_at >= current_date)
  );
$$;

revoke all on function public.is_org_member(uuid), public.is_org_admin(uuid), public.is_org_editor(uuid) from public;
grant execute on function public.is_org_member(uuid), public.is_org_admin(uuid), public.is_org_editor(uuid) to authenticated;

-- ============================================================
-- 2) LIMPIEZA DE POLITICAS PERMISIVAS EXISTENTES
-- ============================================================
do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname='public'
      and tablename in (
        'organizations','organization_members','students','instructors','attendance','payments',
        'exams','competitions','notices','credentials','technical_programs',
        'student_profiles','student_attendance_records','student_payment_records',
        'student_exam_records','student_competition_records'
      )
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- ============================================================
-- 3) ORGANIZACIONES Y MIEMBROS
-- ============================================================
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;

create policy "organizations platform or own active member read"
on public.organizations for select to authenticated
using (public.is_platform_admin() or public.is_org_member(id));

create policy "organizations platform create"
on public.organizations for insert to authenticated
with check (public.is_platform_admin());

create policy "organizations platform or owner admin update"
on public.organizations for update to authenticated
using (public.is_platform_admin() or public.is_org_admin(id))
with check (public.is_platform_admin() or public.is_org_admin(id));

create policy "organizations platform delete"
on public.organizations for delete to authenticated
using (public.is_platform_admin());

create policy "members platform or own org admins read"
on public.organization_members for select to authenticated
using (public.is_platform_admin() or user_id = auth.uid() or public.is_org_admin(organization_id));

create policy "members platform or org admins insert"
on public.organization_members for insert to authenticated
with check (public.is_platform_admin() or public.is_org_admin(organization_id));

create policy "members platform or org admins update"
on public.organization_members for update to authenticated
using (public.is_platform_admin() or public.is_org_admin(organization_id))
with check (public.is_platform_admin() or public.is_org_admin(organization_id));

create policy "members platform or org admins delete"
on public.organization_members for delete to authenticated
using (public.is_platform_admin() or public.is_org_admin(organization_id));

-- ============================================================
-- 4) DATOS OPERATIVOS: AISLAMIENTO POR ORGANIZACION
-- ============================================================
create or replace function public.apply_org_rls(p_table text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- No falla si un modulo opcional aun no existe.
  if to_regclass('public.' || p_table) is null then
    return;
  end if;
  execute format('alter table public.%I enable row level security', p_table);
  execute format('drop policy if exists %I on public.%I', p_table||'_read', p_table);
  execute format('drop policy if exists %I on public.%I', p_table||'_insert', p_table);
  execute format('drop policy if exists %I on public.%I', p_table||'_update', p_table);
  execute format('drop policy if exists %I on public.%I', p_table||'_delete', p_table);
  execute format('create policy %I on public.%I for select to authenticated using (public.is_platform_admin() or public.is_org_member(organization_id))', p_table||'_read', p_table);
  execute format('create policy %I on public.%I for insert to authenticated with check (public.is_platform_admin() or public.is_org_editor(organization_id))', p_table||'_insert', p_table);
  execute format('create policy %I on public.%I for update to authenticated using (public.is_platform_admin() or public.is_org_editor(organization_id)) with check (public.is_platform_admin() or public.is_org_editor(organization_id))', p_table||'_update', p_table);
  execute format('create policy %I on public.%I for delete to authenticated using (public.is_platform_admin() or public.is_org_admin(organization_id))', p_table||'_delete', p_table);
end;
$$;

select public.apply_org_rls(x)
from unnest(array[
  'students','instructors','attendance','payments','exams','competitions','notices','credentials','technical_programs',
  'student_profiles','student_attendance_records','student_payment_records','student_exam_records','student_competition_records'
]) as t(x);

drop function public.apply_org_rls(text);

do $$
begin
  if to_regclass('public.student_profiles') is not null then
    execute $sql$
      create or replace function public.touch_student_profile_updated_at() returns trigger
      language plpgsql as $inner$ begin new.updated_at=now(); return new; end; $inner$;
      drop trigger if exists trg_student_profile_updated_at on public.student_profiles;
      create trigger trg_student_profile_updated_at before update on public.student_profiles
      for each row execute function public.touch_student_profile_updated_at();
    $sql$;
  end if;
end $$;

-- ============================================================
-- 5) AUDITORIA DE PLATAFORMA
-- ============================================================
alter table public.platform_audit_log enable row level security;
drop policy if exists "platform admins manage audit log" on public.platform_audit_log;
create policy "platform admins read audit"
on public.platform_audit_log for select to authenticated
using (public.is_platform_admin());
create policy "platform admins insert audit"
on public.platform_audit_log for insert to authenticated
with check (public.is_platform_admin() and admin_user_id = auth.uid());

create or replace function public.platform_audit(
  p_action text,
  p_org_id uuid default null,
  p_details jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if not public.is_platform_admin() then
    raise exception 'No autorizado';
  end if;
  insert into public.platform_audit_log(admin_user_id, action, organization_id, details)
  values(auth.uid(), p_action, p_org_id, coalesce(p_details,'{}'::jsonb))
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.platform_audit(text,uuid,jsonb) from public;
grant execute on function public.platform_audit(text,uuid,jsonb) to authenticated;

-- ============================================================
-- 6) OPERACIONES DE PLATAFORMA SERVER-SIDE
-- ============================================================
create or replace function public.platform_save_organization(
  p_id uuid,
  p_name text,
  p_plan text,
  p_status text,
  p_expires_at date,
  p_phone text,
  p_email text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if not public.is_platform_admin() then raise exception 'No autorizado'; end if;
  if trim(coalesce(p_name,'')) = '' then raise exception 'El nombre es obligatorio'; end if;
  if p_plan not in ('demo','basico','profesional','premium') then raise exception 'Plan no valido'; end if;
  if p_status not in ('active','suspended','expired') then raise exception 'Estado no valido'; end if;
  if p_id is null then
    insert into public.organizations(name,plan,status,expires_at,phone,email)
    values(trim(p_name),p_plan,p_status,p_expires_at,nullif(trim(p_phone),''),nullif(trim(p_email),''))
    returning id into v_id;
    perform public.platform_audit('organization.created',v_id,jsonb_build_object('name',p_name,'plan',p_plan,'status',p_status));
  else
    update public.organizations
    set name=trim(p_name),plan=p_plan,status=p_status,expires_at=p_expires_at,phone=nullif(trim(p_phone),''),email=nullif(trim(p_email),'' )
    where id=p_id;
    if not found then raise exception 'Organizacion no encontrada'; end if;
    v_id:=p_id;
    perform public.platform_audit('organization.updated',v_id,jsonb_build_object('name',p_name,'plan',p_plan,'status',p_status));
  end if;
  return v_id;
end;
$$;
revoke all on function public.platform_save_organization(uuid,text,text,text,date,text,text) from public;
grant execute on function public.platform_save_organization(uuid,text,text,text,date,text,text) to authenticated;

create or replace function public.platform_assign_member(
  p_org_id uuid,
  p_email text,
  p_role text default 'owner'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_user uuid;
begin
  if not public.is_platform_admin() then raise exception 'No autorizado'; end if;
  if p_role not in ('owner','admin','instructor','viewer') then raise exception 'Rol no valido'; end if;
  select id into v_user from auth.users where lower(email)=lower(trim(p_email)) limit 1;
  if v_user is null then raise exception 'No existe un usuario de Auth con ese correo'; end if;
  insert into public.organization_members(organization_id,user_id,role)
  values(p_org_id,v_user,p_role)
  on conflict (organization_id,user_id) do update set role=excluded.role;
  perform public.platform_audit('member.assigned',p_org_id,jsonb_build_object('email',p_email,'role',p_role));
  return v_user;
end;
$$;
revoke all on function public.platform_assign_member(uuid,text,text) from public;
grant execute on function public.platform_assign_member(uuid,text,text) to authenticated;

create or replace function public.platform_get_members(p_org_id uuid)
returns table(user_id uuid,email text,role text)
language sql
stable
security definer
set search_path = public
as $$
  select om.user_id, au.email::text, om.role
  from public.organization_members om
  join auth.users au on au.id=om.user_id
  where om.organization_id=p_org_id
    and public.is_platform_admin();
$$;
revoke all on function public.platform_get_members(uuid) from public;
grant execute on function public.platform_get_members(uuid) to authenticated;

-- ============================================================
-- 7) ADMINISTRADOR DE PLATAFORMA
-- ============================================================
-- Cambia SOLO el correo si la cuenta administradora es otra.
insert into public.platform_admins(user_id)
select id from auth.users where lower(email)=lower('julio.salazar.flores@hotmail.com')
limit 1
on conflict (user_id) do nothing;

-- Verificacion final
select
  (select count(*) from public.organizations) as organizations_count,
  (select count(*) from public.platform_admins) as platform_admins_count;

-- ============================================================
-- 8) PROTECCION DE CONFIGURACION COMERCIAL Y MARCA
-- ============================================================
create or replace function public.protect_platform_fields_on_organization()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  oldj jsonb := to_jsonb(old);
  newj jsonb := to_jsonb(new);
  k text;
begin
  if public.is_platform_admin() then return new; end if;
  if new.plan is distinct from old.plan
     or new.status is distinct from old.status
     or new.expires_at is distinct from old.expires_at then
    raise exception 'Los campos de plan, estado y vigencia son administrados por JSF & MAFIGO';
  end if;
  foreach k in array array['logo_url','logo','logo_path','brand_logo_url','platform_brand'] loop
    if newj ? k and (newj->k) is distinct from (oldj->k) then
      raise exception 'Los activos de marca son administrados por JSF & MAFIGO';
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_protect_platform_fields on public.organizations;
create trigger trg_protect_platform_fields
before update on public.organizations
for each row execute function public.protect_platform_fields_on_organization();
