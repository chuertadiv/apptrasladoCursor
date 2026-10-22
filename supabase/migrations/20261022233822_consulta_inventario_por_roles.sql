grant usage on schema traslado to authenticated;
grant select on traslado.usuario_roles, traslado.bienes to authenticated;

create policy usuario_lee_roles_propios on traslado.usuario_roles
for select to authenticated using (usuario_id = (select auth.uid()));

create policy operador_lee_bienes on traslado.bienes
for select to authenticated using (
 exists (select 1 from traslado.usuario_roles r where r.usuario_id = (select auth.uid()))
);

create function public.traslado_mis_roles()
returns table(rol text)
language plpgsql stable security invoker set search_path = ''
as $$
begin
 if auth.uid() is null then
   raise exception 'Inicia sesión para continuar' using errcode = '42501';
 end if;
 return query select r.rol from traslado.usuario_roles r
 where r.usuario_id = auth.uid() order by r.rol;
end;
$$;
revoke all on function public.traslado_mis_roles() from public, anon, authenticated, service_role;
grant execute on function public.traslado_mis_roles() to authenticated;

create function public.traslado_buscar_bien(p_codigo text)
returns table (
 id uuid, codigo_censo text, nombre text, ubicacion_origen text,
 codigo_activo_fijo text, codigo_alternativo text,
 estado_fisico_origen text, estado_etiquetas text, fotos_bien jsonb, fotos_serial jsonb
)
language plpgsql stable security invoker set search_path = ''
as $$
begin
 if auth.uid() is null or not exists (
   select 1 from traslado.usuario_roles r where r.usuario_id = auth.uid()
 ) then
   raise exception 'No tienes un rol autorizado para consultar el inventario' using errcode = '42501';
 end if;
 if p_codigo is null or length(trim(p_codigo)) = 0 or length(p_codigo)>256 then
   raise exception 'Código de censo inválido' using errcode = '22023';
 end if;
 return query
 select b.id,b.codigo_censo,b.nombre,b.ubicacion_origen,b.codigo_activo_fijo,
 b.codigo_alternativo,b.estado_fisico_origen,b.estado_etiquetas,b.fotos_bien,b.fotos_serial
 from traslado.bienes b where b.codigo_censo=trim(p_codigo);
end;
$$;
revoke all on function public.traslado_buscar_bien(text) from public, anon, authenticated, service_role;
grant execute on function public.traslado_buscar_bien(text) to authenticated;
comment on function public.traslado_buscar_bien(text) is
 'Consulta exacta por código de censo. Requiere sesión y rol registrado; sin escritura ni elevación de privilegios.';
notify pgrst, 'reload schema';
