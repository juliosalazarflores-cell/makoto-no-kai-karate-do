-- ETAPA: Expediente integral de alumnos
-- Ejecutar UNA VEZ en Supabase SQL Editor.
-- Requiere que public.students y public.organization_members ya existan.

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

create table if not exists public.student_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  student_id uuid not null unique references public.students(id) on delete cascade,
  photo_url text,
  grade_history text,
  medical_notes text,
  allergies text,
  emergency_contact_name text,
  emergency_contact_phone text,
  insurance_info text,
  consent_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.student_attendance_records (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade, attendance_date date not null,
  status text not null default 'Presente', notes text, created_at timestamptz not null default now()
);
create index if not exists idx_student_attendance_student on public.student_attendance_records(student_id, attendance_date desc);

create table if not exists public.student_payment_records (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade, payment_date date not null,
  amount numeric(12,2) not null default 0, concept text, status text not null default 'Pagado', notes text, created_at timestamptz not null default now()
);
create index if not exists idx_student_payments_student on public.student_payment_records(student_id, payment_date desc);

create table if not exists public.student_exam_records (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade, exam_date date not null,
  title text, grade text, result text, cost numeric(12,2) default 0, notes text, created_at timestamptz not null default now()
);
create index if not exists idx_student_exams_student on public.student_exam_records(student_id, exam_date desc);

create table if not exists public.student_competition_records (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade, event_date date not null,
  name text, category text, result text, notes text, created_at timestamptz not null default now()
);
create index if not exists idx_student_competitions_student on public.student_competition_records(student_id, event_date desc);

alter table public.student_profiles enable row level security;
alter table public.student_attendance_records enable row level security;
alter table public.student_payment_records enable row level security;
alter table public.student_exam_records enable row level security;
alter table public.student_competition_records enable row level security;

create policy "org members manage student profiles" on public.student_profiles for all to authenticated using (is_org_member(organization_id)) with check (is_org_member(organization_id));
create policy "org members manage student attendance records" on public.student_attendance_records for all to authenticated using (is_org_member(organization_id)) with check (is_org_member(organization_id));
create policy "org members manage student payment records" on public.student_payment_records for all to authenticated using (is_org_member(organization_id)) with check (is_org_member(organization_id));
create policy "org members manage student exam records" on public.student_exam_records for all to authenticated using (is_org_member(organization_id)) with check (is_org_member(organization_id));
create policy "org members manage student competition records" on public.student_competition_records for all to authenticated using (is_org_member(organization_id)) with check (is_org_member(organization_id));

-- Mantener updated_at sin depender de triggers externos.
create or replace function public.touch_student_profile_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end; $$;
drop trigger if exists trg_student_profile_updated_at on public.student_profiles;
create trigger trg_student_profile_updated_at before update on public.student_profiles for each row execute function public.touch_student_profile_updated_at();
