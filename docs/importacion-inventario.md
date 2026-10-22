# Importación del inventario

## Revisión del archivo recibido

Hoja Respuestas: 7.913 filas de datos, 20 columnas. Código de Censo de Inventario: 7.430 valores distintos, sin vacíos y almacenados como texto. Hay 177 códigos repetidos que representan 483 filas adicionales. Este archivo es un historial; no importar una fila como un bien distinto automáticamente.

## Mapeo

| Columna Excel | Destino en bienes |
| --- | --- |
| Código de Censo de Inventario | codigo_censo (texto único) |
| Nombre | nombre |
| Ubicación de Inventario | ubicacion_origen |
| Código de Inventario Activo Fijo | codigo_activo_fijo (texto) |
| Código Alternativo | codigo_alternativo (texto) |
| Estado físico / funcional | estado_fisico_origen |
| Estado de las etiquetas | estado_etiquetas |
| Foto del bien | fotos_bien (lista JSON de referencias) |
| Foto etiqueta fabricante / Serial | fotos_serial (lista JSON de referencias) |

Todas las columnas originales, incluidas ID respuesta, Usuario, Grupo, Enviado, Estado, Versión formulario, Replicado por, Fecha réplica, Cantidad Etiquetas Reemplazar y Aprueba Inventario, se conservan en inventario_historial.datos_originales. No confundir el estado del formulario con el estado del traslado.

## Procedimiento previsto

1. Calcular SHA256 del archivo para impedir reimportación accidental.
2. Ingresar todas las filas a inventario_historial con hoja y número de fila como procedencia.
3. Validar el código como texto, sin convertirlo a número ni alterar ceros iniciales. Conservar el valor original en JSON.
4. Separar los códigos repetidos para conciliación. No elegir la primera fila ni la última sin una regla aprobada. Conservar cada registro histórico.
5. Poblar bienes desde el registro conciliado y vincular fuente_historial_id.
6. Guardar referencias de fotografías sin descargarlas ni hacerlas públicas. Las referencias del Excel apuntan a otro proyecto Supabase; no asumir que existen en el proyecto de traslado.

Pendiente: confirmar si el QR contiene directamente el código de censo o una URL que lo incluye. La existencia de la columna no demuestra el formato físico del QR.

## Alcance de la migración inicial

La migración crea un esquema nuevo traslado y no modifica tablas existentes. Es deliberadamente no reejecutable: si el esquema ya existe, debe abortar y revisarse. RLS está habilitada en todas las tablas sin políticas de acceso y los clientes anon/authenticated no tienen permisos sobre el esquema. No exponerlo aún en Data API.

Faltan las RPC y las políticas por rol para sellar, asignar, despachar y recibir de forma transaccional. Estas deberán bloquear modificaciones al contenido tras sellado/despacho, verificar pertenencia de bienes en recepción, impedir cierre con lotes pendientes, validar idempotencia y gestionar reaperturas autorizadas. El índice único de bienes activos y la asignación única del lote a un viaje ya están modelados; no equivalen a tener el flujo operativo implementado.

La auditoría y los manifiestos rechazan UPDATE/DELETE por trigger. Los administradores de base pueden alterar el esquema: no se afirma inmutabilidad frente a administradores.

## Estado de ejecución

SQL versionado como base de desarrollo. No ejecutado ni probado contra PostgreSQL/Supabase. No se han creado tablas remotas ni importado datos: la clave publishable no permite DDL. Ejecutar solo tras revisar el proyecto mediante una conexión administrativa autorizada o el editor SQL de Supabase. No publicar el Excel ni datos reales en el repositorio público.
