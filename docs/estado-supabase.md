# Estado de Supabase

La migración base_traslado fue aplicada correctamente al proyecto autorizado el 22 de octubre de 2026. Supabase la registró con versión 20261022233544. Corresponde al archivo inicial supabase/migrations/202610220001_base_traslado.sql del repositorio; no volver a ejecutar ese archivo contra este proyecto. La numeración del archivo inicial precede a la conexión administrativa y difiere de la versión asignada por Supabase: al preparar el flujo CLI se deberá conciliar el historial antes de usar db push.

Se crearon 13 tablas en el esquema traslado, con RLS habilitada y sin acceso USAGE para anon/authenticated. Se verificaron los triggers de inmutabilidad de eventos y manifiestos. No se cargaron bienes, no se crearon usuarios y no se expuso el esquema para uso desde la app.

El asesor de seguridad solo devolvió avisos informativos RLS Enabled No Policy para estas tablas: el acceso está cerrado intencionalmente hasta implementar funciones transaccionales y permisos por rol. Referencia: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy

Esta ejecución actualiza las notas anteriores que indicaban que el SQL no se había ejecutado. La aplicación y la carga de inventario siguen pendientes de implementación/integración.
