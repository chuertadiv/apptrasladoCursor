# Consulta de inventario por roles

Migración aplicada al proyecto autorizado: 20261022233822_consulta_inventario_por_roles.

## API para la app

Con sesión Supabase activa:
- supabase.rpc('traslado_mis_roles'): devuelve únicamente roles del usuario actual.
- supabase.rpc('traslado_buscar_bien', { p_codigo: codigo }): búsqueda exacta por código de censo. Devuelve lista vacía si no existe y error 42501 si el usuario no tiene un rol autorizado.

El QR se tratará como código de censo textual. Sigue pendiente comprobar el contenido de un QR físico para decidir si se necesita extraer el código desde una URL.

Todos los roles operativos definidos pueden consultar bienes. Se usan funciones SECURITY INVOKER con search_path vacío y políticas RLS que consultan la asignación real de roles; no se confía en metadata editable por el usuario.

Los usuarios autenticados pueden leer solo sus roles y los bienes si tienen algún rol asignado. No tienen permisos de escritura sobre estas tablas ni sobre las otras tablas de traslado. No se habilita autoasignación de roles ni registro abierto como administrador. El resto de las operaciones aún no está implementado.

## Verificación

Pruebas ejecutadas en PostgreSQL con datos sintéticos dentro de una transacción revertida:
- Roles múltiples del usuario actual.
- Consulta autorizada de un bien y búsqueda de código inexistente.
- Rechazo de código vacío.
- Rechazo de autoasignación de administrador.
- Rechazo de modificación directa de bienes.
- Aislamiento de roles ajenos y bloqueo de lectura para usuario sin rol.
- Bloqueo de RPC para usuario sin rol, sesión sin identidad y rol anónimo.

Las pruebas no conservan usuarios ni bienes. El asesor de seguridad devuelve solo avisos informativos para las once tablas que siguen cerradas sin políticas: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy

El esquema traslado ahora tiene USAGE para authenticated; no para anon. Esta nota actualiza el estado inicial registrado en estado-supabase.md. No se ha cargado inventario real ni se han provisionado usuarios operativos.

Pendiente: carga administrativa de inventario, gestión de roles, operaciones de embalaje/despacho/recepción, interfaz móvil y generación APK.
