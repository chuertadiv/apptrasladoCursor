-- Base inicial. Revisar y ejecutar mediante Supabase SQL Editor.
-- No incluye inventario real ni credenciales. No habilita todavía operaciones desde la app.
begin;
create schema traslado;
create table traslado.usuario_roles (
 usuario_id uuid not null references auth.users(id),
 rol text not null check (rol in ('administrador','inventario','origen','embalaje','coordinador','despacho','recepcion','supervisor')),
 primary key(usuario_id,rol)
);
create table traslado.importaciones (
 id uuid primary key default gen_random_uuid(),
 archivo_nombre text not null,
 archivo_sha256 text not null unique,
 creado_por uuid not null references auth.users(id),
 creado_en timestamptz not null default now()
);
-- Una fila por registro fuente. Nunca descartar históricos por compartir código de censo.
create table traslado.inventario_historial (
 id uuid primary key default gen_random_uuid(),
 importacion_id uuid not null references traslado.importaciones(id),
 hoja text not null,
 fila_excel integer not null check(fila_excel > 1),
 codigo_censo text not null check(length(trim(codigo_censo)) > 0),
 datos_originales jsonb not null,
 unique(importacion_id,hoja,fila_excel)
);
create index on traslado.inventario_historial(codigo_censo);
-- El registro vigente se selecciona explícitamente al conciliar el historial.
create table traslado.bienes (
 id uuid primary key default gen_random_uuid(),
 codigo_censo text not null unique check(codigo_censo = trim(codigo_censo) and length(codigo_censo)>0),
 nombre text not null,
 ubicacion_origen text,
 codigo_activo_fijo text,
 codigo_alternativo text,
 estado_fisico_origen text,
 estado_etiquetas text,
 fotos_bien jsonb not null default '[]',
 fotos_serial jsonb not null default '[]',
 fuente_historial_id uuid not null references traslado.inventario_historial(id),
 creado_en timestamptz not null default now()
);
create table traslado.viajes (
 id uuid primary key default gen_random_uuid(),
 codigo text not null unique,
 coordinador_id uuid not null references auth.users(id),
 origen text not null default 'Fantasilandia',
 destino text not null default 'Parque Sur',
 estado text not null default 'planificado' check(estado in ('planificado','despachado','cerrado','cancelado')),
 recordatorio_guia_mostrado_en timestamptz,
 salida_en timestamptz,
 cerrado_en timestamptz,
 version integer not null default 1
);
create table traslado.lotes (
 id uuid primary key default gen_random_uuid(),
 codigo text not null unique,
 origen text not null default 'Fantasilandia',
 destino text not null default 'Parque Sur',
 resumen_contenido text not null,
 precinto text,
 estado text not null default 'abierto' check(estado in ('abierto','sellado','despachado','recibido','anulado')),
 creado_por uuid not null references auth.users(id),
 creado_en timestamptz not null default now(),
 version integer not null default 1
);
create table traslado.lote_bienes (
 lote_id uuid not null references traslado.lotes(id),
 bien_id uuid not null references traslado.bienes(id),
 incorporado_por uuid not null references auth.users(id),
 incorporado_en timestamptz not null default now(),
 retirado_en timestamptz,
 primary key(lote_id,bien_id)
);
create unique index bien_un_lote_activo on traslado.lote_bienes(bien_id) where retirado_en is null;
-- Un lote tiene una sola asignación a viaje: no hay cantidades parciales.
create table traslado.viaje_lotes (
 lote_id uuid primary key references traslado.lotes(id),
 viaje_id uuid not null references traslado.viajes(id),
 asignado_por uuid not null references auth.users(id),
 asignado_en timestamptz not null default now()
);
create index on traslado.viaje_lotes(viaje_id);
create table traslado.manifiestos (
 viaje_id uuid primary key references traslado.viajes(id),
 contenido jsonb not null,
 generado_por uuid not null references auth.users(id),
 generado_en timestamptz not null default now()
);
create table traslado.recepciones (
 id uuid primary key default gen_random_uuid(),
 lote_id uuid not null unique references traslado.lotes(id),
 recibido_por uuid not null references auth.users(id),
 recibido_en timestamptz not null default now(),
 precinto_intacto boolean not null,
 verificacion_individual_completa boolean not null default false,
 estado text not null check(estado in ('en_revision','conforme','con_incidencias')),
 check(estado='en_revision' or precinto_intacto or verificacion_individual_completa)
);
create table traslado.recepcion_detalles (
 recepcion_id uuid not null references traslado.recepciones(id),
 bien_id uuid not null references traslado.bienes(id),
 resultado text not null check(resultado in ('conforme','danado','faltante')),
 observacion text,
 primary key(recepcion_id,bien_id)
);
create table traslado.incidencias (
 id uuid primary key default gen_random_uuid(),
 recepcion_id uuid not null references traslado.recepciones(id),
 bien_id uuid references traslado.bienes(id),
 tipo text not null check(tipo in ('dano','faltante','precinto','otro')),
 descripcion text not null,
 rutas_evidencias jsonb not null default '[]',
 registrado_por uuid not null references auth.users(id),
 registrado_en timestamptz not null default now()
);
create table traslado.trazabilidad_eventos (
 id uuid primary key default gen_random_uuid(),
 operacion_id uuid not null,
 secuencia integer not null default 1,
 tipo text not null,
 bien_id uuid references traslado.bienes(id),
 lote_id uuid references traslado.lotes(id),
 viaje_id uuid references traslado.viajes(id),
 actor_id uuid not null references auth.users(id),
 ocurrido_en timestamptz not null,
 registrado_en timestamptz not null default now(),
 datos jsonb not null,
 unique(operacion_id,secuencia),
 check(num_nonnulls(bien_id,lote_id,viaje_id)>0)
);
create function traslado.rechazar_mutacion() returns trigger language plpgsql set search_path='' as $$
begin
 raise exception 'Registro inmutable: registrar una corrección mediante un nuevo evento';
end;
$$;
create trigger eventos_inmutables before update or delete on traslado.trazabilidad_eventos
 for each row execute function traslado.rechazar_mutacion();
create trigger manifiestos_inmutables before update or delete on traslado.manifiestos
 for each row execute function traslado.rechazar_mutacion();
-- Denegación por defecto hasta implementar RPC transaccionales y políticas por rol.
-- No exponer esquema traslado en Data API todavía.
do $$
declare t record;
begin
 for t in select tablename from pg_tables where schemaname='traslado' loop
 execute format('alter table traslado.%I enable row level security', t.tablename);
 end loop;
end;
$$;
revoke all on schema traslado from public, anon, authenticated;
revoke all on all tables in schema traslado from public, anon, authenticated;
revoke all on all functions in schema traslado from public, anon, authenticated;
comment on schema traslado is 'Base restringida. Pendiente: RPC, permisos por rol, congelamiento y cierre transaccionales.';
commit;
