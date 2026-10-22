begin;
do $$
declare
 u uuid := gen_random_uuid(); other_u uuid := gen_random_uuid();
 imp uuid := gen_random_uuid(); hist uuid := gen_random_uuid();
 code text := 'PRUEBA-' || gen_random_uuid()::text;
begin
 insert into auth.users(id) values(u),(other_u);
 insert into traslado.usuario_roles(usuario_id,rol) values(u,'inventario'),(u,'embalaje');
 insert into traslado.importaciones(id,archivo_nombre,archivo_sha256,creado_por)
 values(imp,'prueba-transaccional',gen_random_uuid()::text,u);
 insert into traslado.inventario_historial(id,importacion_id,hoja,fila_excel,codigo_censo,datos_originales)
 values(hist,imp,'Prueba',2,code,'{}');
 insert into traslado.bienes(codigo_censo,nombre,fuente_historial_id)
 values(code,'Bien sintético de prueba',hist);
 perform set_config('test.uid',u::text,true);
 perform set_config('test.other_uid',other_u::text,true);
 perform set_config('test.code',code,true);
 perform set_config('request.jwt.claims',json_build_object('sub',u,'role','authenticated')::text,true);
end;
$$;
set local role authenticated;
do $$
begin
 if (select count(*) from public.traslado_mis_roles()) <> 2 then raise exception 'Fallo: roles múltiples'; end if;
 if (select count(*) from public.traslado_buscar_bien(current_setting('test.code'))) <> 1 then raise exception 'Fallo: lectura autorizada'; end if;
 if (select count(*) from public.traslado_buscar_bien('CODIGO-INEXISTENTE-PRUEBA')) <> 0 then raise exception 'Fallo: búsqueda inexistente'; end if;
 begin
   perform * from public.traslado_buscar_bien(' ');
   raise exception 'Fallo: acepta código vacío';
 exception when invalid_parameter_value then null;
 end;
 begin
   insert into traslado.usuario_roles(usuario_id,rol) values(auth.uid(),'administrador');
   raise exception 'Fallo: autoasignación de administrador';
 exception when insufficient_privilege then null;
 end;
 begin
   update traslado.bienes set nombre='Cambio no permitido' where codigo_censo=current_setting('test.code');
   raise exception 'Fallo: escritura directa permitida';
 exception when insufficient_privilege then null;
 end;
 perform set_config('request.jwt.claims',json_build_object('sub',current_setting('test.other_uid'),'role','authenticated')::text,true);
 if (select count(*) from traslado.usuario_roles) <> 0 then raise exception 'Fallo: lectura de roles ajenos'; end if;
 if (select count(*) from traslado.bienes) <> 0 then raise exception 'Fallo: lectura sin rol'; end if;
 begin
   perform * from public.traslado_buscar_bien(current_setting('test.code'));
   raise exception 'Fallo: RPC permite usuario sin rol';
 exception when insufficient_privilege then null;
 end;
 perform set_config('request.jwt.claims','{}',true);
 begin
   perform * from public.traslado_mis_roles();
   raise exception 'Fallo: acepta sesión sin identidad';
 exception when insufficient_privilege then null;
 end;
end;
$$;
set local role anon;
do $$
begin
 begin
   perform * from public.traslado_buscar_bien(current_setting('test.code'));
   raise exception 'Fallo: acceso anónimo a RPC';
 exception when insufficient_privilege then null;
 end;
end;
$$;
reset role;
rollback;
select 'Pruebas de permisos correctas; datos sintéticos revertidos' as resultado;
