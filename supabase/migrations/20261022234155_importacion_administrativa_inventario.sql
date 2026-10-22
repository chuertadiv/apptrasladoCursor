grant select, insert on traslado.importaciones, traslado.inventario_historial to authenticated;
grant insert on traslado.bienes to authenticated;

create policy admin_lee_importaciones on traslado.importaciones for select to authenticated
using (exists(select 1 from traslado.usuario_roles where usuario_id=(select auth.uid()) and rol='administrador'));
create policy admin_crea_importacion on traslado.importaciones for insert to authenticated
with check (creado_por=(select auth.uid()) and exists(select 1 from traslado.usuario_roles where usuario_id=(select auth.uid()) and rol='administrador'));
create policy admin_lee_historial on traslado.inventario_historial for select to authenticated
using (exists(select 1 from traslado.usuario_roles where usuario_id=(select auth.uid()) and rol='administrador'));
create policy admin_crea_historial on traslado.inventario_historial for insert to authenticated
with check (exists(select 1 from traslado.usuario_roles where usuario_id=(select auth.uid()) and rol='administrador')
 and exists(select 1 from traslado.importaciones i where i.id=importacion_id and i.creado_por=(select auth.uid())));
create policy admin_crea_bienes on traslado.bienes for insert to authenticated
with check (exists(select 1 from traslado.usuario_roles where usuario_id=(select auth.uid()) and rol='administrador')
 and exists(select 1 from traslado.inventario_historial h join traslado.importaciones i on i.id=h.importacion_id
 where h.id=fuente_historial_id and h.codigo_censo=bienes.codigo_censo and i.creado_por=(select auth.uid())));

create function public.traslado_importar_inventario(p_datos jsonb)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 actor uuid := auth.uid();
 archivo_hash text;
 import_id uuid;
 existing_id uuid;
 h jsonb;
 b jsonb;
 n_hist integer;
 n_bienes integer;
begin
 if actor is null or not exists(select 1 from traslado.usuario_roles where usuario_id=actor and rol='administrador') then
   raise exception 'Solo el administrador puede cargar inventario' using errcode='42501';
 end if;
 if jsonb_typeof(p_datos) is distinct from 'object'
 or jsonb_typeof(p_datos->'importacion') is distinct from 'object'
 or jsonb_typeof(p_datos->'inventario_historial') is distinct from 'array'
 or jsonb_typeof(p_datos->'bienes') is distinct from 'array' then
   raise exception 'Estructura de importación inválida' using errcode='22023';
 end if;
 archivo_hash := lower(p_datos->'importacion'->>'archivo_sha256');
 if archivo_hash is null or archivo_hash !~ '^[0-9a-f]{64}$'
 or coalesce(length(trim(p_datos->'importacion'->>'archivo_nombre')),0)=0 then
   raise exception 'Nombre o SHA256 inválido' using errcode='22023';
 end if;
 n_hist := jsonb_array_length(p_datos->'inventario_historial');
 n_bienes := jsonb_array_length(p_datos->'bienes');
 if n_hist<1 or n_bienes<1 or n_hist>20000 or n_bienes>n_hist then
   raise exception 'La carga debe contener entre 1 y 20000 registros fuente y al menos un bien' using errcode='22023';
 end if;
 -- Serialize same-file retries. The unique SHA constraint remains the final guard.
 perform pg_advisory_xact_lock(hashtextextended(archivo_hash,0));
 select id into existing_id from traslado.importaciones where archivo_sha256=archivo_hash;
 if existing_id is not null then
   return jsonb_build_object('estado','ya_importado','importacion_id',existing_id);
 end if;
 if exists(select 1 from jsonb_array_elements(p_datos->'bienes') e
   group by e->>'codigo_censo' having count(*)>1) then
   raise exception 'La selección contiene códigos repetidos' using errcode='22023';
 end if;
 import_id := gen_random_uuid();
 insert into traslado.importaciones(id,archivo_nombre,archivo_sha256,creado_por)
 values(import_id,p_datos->'importacion'->>'archivo_nombre',archivo_hash,actor);
 for h in select value from jsonb_array_elements(p_datos->'inventario_historial') loop
   if jsonb_typeof(h->'datos_originales') is distinct from 'object'
   or jsonb_typeof(h->'codigo_censo') is distinct from 'string'
   or h->>'codigo_censo' is distinct from trim(h->'datos_originales'->>'Código de Censo de Inventario') then
     raise exception 'Código del historial no coincide con su fuente' using errcode='22023';
   end if;
   insert into traslado.inventario_historial(id,importacion_id,hoja,fila_excel,codigo_censo,datos_originales)
   values((h->>'id')::uuid,import_id,h->>'hoja',(h->>'fila_excel')::integer,h->>'codigo_censo',h->'datos_originales');
 end loop;
 for b in select value from jsonb_array_elements(p_datos->'bienes') loop
   if jsonb_typeof(b->'codigo_censo') is distinct from 'string'
   or coalesce(length(trim(b->>'nombre')),0)=0
   or jsonb_typeof(b->'fotos_bien') is distinct from 'array'
   or jsonb_typeof(b->'fotos_serial') is distinct from 'array'
   or not exists(select 1 from traslado.inventario_historial s where s.id=(b->>'fuente_historial_id')::uuid
     and s.importacion_id=import_id and s.codigo_censo=b->>'codigo_censo') then
     raise exception 'Bien inválido o sin fuente en esta importación' using errcode='22023';
   end if;
   insert into traslado.bienes(codigo_censo,nombre,ubicacion_origen,codigo_activo_fijo,codigo_alternativo,
     estado_fisico_origen,estado_etiquetas,fotos_bien,fotos_serial,fuente_historial_id)
   values(b->>'codigo_censo',b->>'nombre',b->>'ubicacion_origen',b->>'codigo_activo_fijo',b->>'codigo_alternativo',
     b->>'estado_fisico_origen',b->>'estado_etiquetas',b->'fotos_bien',b->'fotos_serial',(b->>'fuente_historial_id')::uuid);
 end loop;
 if n_bienes <> (select count(distinct codigo_censo) from traslado.inventario_historial where importacion_id=import_id) then
   raise exception 'Faltan códigos en la selección de bienes' using errcode='22023';
 end if;
 return jsonb_build_object('estado','importado','importacion_id',import_id,'bienes',n_bienes,'registros_fuente',n_hist);
end;
$$;
revoke all on function public.traslado_importar_inventario(jsonb) from public, anon, authenticated, service_role;
grant execute on function public.traslado_importar_inventario(jsonb) to authenticated;
comment on function public.traslado_importar_inventario(jsonb) is 'Carga inicial administrativa atómica. No actualiza bienes existentes. Sin SECURITY DEFINER.';
notify pgrst, 'reload schema';
