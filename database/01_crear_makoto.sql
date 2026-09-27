-- Crear la organización de prueba y vincular al administrador existente.
-- Ejecutar en Supabase SQL Editor como administrador del proyecto.

with new_org as (
  insert into public.organizations (name, phone, email, status, plan)
  values ('Makoto-No-Kai Karate-Do', '', '', 'active', 'demo')
  on conflict do nothing
  returning id
)
insert into public.organization_members (organization_id, user_id, role)
select o.id, u.id, 'owner'
from (
  select id from new_org
  union all
  select id from public.organizations where name = 'Makoto-No-Kai Karate-Do' limit 1
) o
cross join lateral (
  select id from auth.users where email = 'julio.salazar.flores@hotmail.com' limit 1
) u
on conflict (organization_id, user_id) do update set role='owner';

-- Verificación
select o.id as organization_id, o.name, om.user_id, om.role
from public.organizations o
join public.organization_members om on om.organization_id = o.id
join auth.users u on u.id = om.user_id
where o.name = 'Makoto-No-Kai Karate-Do'
  and u.email = 'julio.salazar.flores@hotmail.com';
