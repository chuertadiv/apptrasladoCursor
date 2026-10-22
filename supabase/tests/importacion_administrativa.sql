begin;
do $$
declare a uuid:=gen_random_uuid(); o uuid:=gen_random_uuid(); h uuid:=gen_random_uuid();
 code text:='00001-PRUEBA-'||gen_random_uuid()::text; payload jsonb;
begin
 insert into auth.users(id) values(a),(o);
 insert into traslado.usuario_roles(usuario_id,rol) values(a,'administrador'),(o,'embalaje');
 payload:=jsonb_build_object(
 'importacion',jsonb_build_object('archivo_nombre','prueba.xlsx','archivo_sha256',repeat('a',32)||replace(gen_random_uuid()::text,'-','')),
 'inventario_historial',jsonb_build_array(jsonb_build_object('id',h,'hoja','Prueba','fila_excel',2,
   'codigo_censo',code,'datos_originales',jsonb_build_object('Código de Censo de Inventario',code))),
 'bienes',jsonb_build_array(jsonb_build_object('codigo_censo',code,'nombre','Bien sintético',
   'fuente_historial_id',h,'fotos_bien','[]'::jsonb,'fotos_serial','[]'::jsonb)));
 perform set_config('test.payload',payload::text,true);
 perform set_config('test.operator',o::text,true);
 perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated')::text,true);
end;
$$;
set local role authenticated;
do $$
declare p jsonb:=current_setting('test.payload')::jsonb; r jsonb; bad jsonb; n integer;
begin
 r:=public.traslado_importar_inventario(p);
 if r->>'estado'<>'importado' or (r->>'bienes')::integer<>1 then raise exception 'Fallo: carga válida'; end if;
 if not exists(select 1 from traslado.importaciones where id=(r->>'importacion_id')::uuid and creado_por=auth.uid()) then raise exception 'Fallo: autor'; end if;
 r:=public.traslado_importar_inventario(p);
 if r->>'estado'<>'ya_importado' then raise exception 'Fallo: idempotencia'; end if;
 if (select count(*) from traslado.bienes where codigo_censo=p->'bienes'->0->>'codigo_censo')<>1 then raise exception 'Fallo: duplicación'; end if;
 select count(*) into n from traslado.importaciones;
 -- A different file with a conflicting history UUID must roll back its batch header too.
 bad:=jsonb_set(p,'{importacion,archivo_sha256}',to_jsonb(repeat('b',32)||replace(gen_random_uuid()::text,'-','')));
 begin
   perform public.traslado_importar_inventario(bad);
   raise exception 'Fallo: aceptó conflicto';
 exception when unique_violation then null;
 end;
 if (select count(*) from traslado.importaciones)<>n then raise exception 'Fallo: importación parcial'; end if;
 -- Duplicate selected codes fail validation before inserts.
 bad:=jsonb_set(bad,'{bienes}',(p->'bienes')||(p->'bienes'));
 -- Add a second source row so shape validation does not mask duplicate-code validation.
 bad:=jsonb_set(bad,'{inventario_historial}',(p->'inventario_historial')||(p->'inventario_historial'));
 begin
   perform public.traslado_importar_inventario(bad);
   raise exception 'Fallo: acepta selección duplicada';
 exception when invalid_parameter_value then null;
 end;
 perform set_config('request.jwt.claims',json_build_object('sub',current_setting('test.operator'),'role','authenticated')::text,true);
 begin
   perform public.traslado_importar_inventario(p);
   raise exception 'Fallo: operador puede importar';
 exception when insufficient_privilege then null;
 end;
 if (select count(*) from traslado.importaciones)<>0 then raise exception 'Fallo: historial administrativo visible'; end if;
 begin
   insert into traslado.importaciones(archivo_nombre,archivo_sha256,creado_por) values('No permitido',gen_random_uuid()::text,auth.uid());
   raise exception 'Fallo: operador inserta por tabla';
 exception when insufficient_privilege then null;
 end;
end;
$$;
set local role anon;
do $$
begin
 begin
   perform public.traslado_importar_inventario(current_setting('test.payload')::jsonb);
   raise exception 'Fallo: permite importar a anónimo';
 exception when insufficient_privilege then null;
 end;
end;
$$;
reset role;
rollback;
select 'Carga administrativa, autor, idempotencia, rollback y permisos: correctos; datos de prueba revertidos' as resultado;