# App Traslado

Sistema de trazabilidad de bienes desde Fantasilandia hacia Parque Sur.

Estado: definición inicial. Todavía no hay aplicación ejecutable ni APK.

## Reglas confirmadas

- Utilizar la base de bienes y los QR individuales existentes, conservando sus identificadores.
- Agrupar bienes en lotes con identificador único y QR maestro. La etiqueta mostrará origen, destino, cantidad y resumen del contenido; al escanear se consultará el detalle completo.
- Un viaje puede transportar varios lotes. Todos viajan completos: no se divide un lote entre viajes.
- Un bien no puede integrar simultáneamente dos lotes activos.
- Al confirmar el despacho se congela el contenido de los lotes y la lista de lotes del viaje.
- El transporte es externo. Registrar al coordinador interno; no exigir identificación del conductor ni usuarios de la empresa transportista.
- Recordar al encargado que debe generar la guía de despacho en el ERP. La app no la genera ni se integra al ERP en esta etapa.
- Despacho no equivale a recepción. Documentar por lote el responsable de recepción, faltantes, daños y fotografías.
- Ante un precinto vulnerado se exige verificación individual.
- Cerrar el viaje cuando todos sus lotes tengan recepción documentada, incluidas las incidencias.
- Conservar historial de eventos sin edición desde la app. Las correcciones generan eventos nuevos.

## Arquitectura propuesta

React + TypeScript + Vite y Capacitor para Android APK y versión web. Supabase Auth, PostgreSQL y Storage con permisos de servidor y RLS. Arquitectura hexagonal para separar dominio, casos de uso y adaptadores.

Operación offline con almacenamiento local persistente y cola de sincronización. Aplicar idempotencia y validar conflictos en servidor. Una operación pendiente local no equivale a una confirmación del servidor.

## Desarrollo en GitHub

- main: entregas integradas.
- feature/*: funcionalidades revisadas mediante pull requests.
- Versionar código, migraciones SQL, documentación y automatización de pruebas y compilación.
- No publicar contraseñas, claves privadas ni datos reales del inventario.

## Entregas previstas

1. Base del proyecto, autenticación, roles múltiples y conexión al inventario existente.
2. Lectura QR, creación y agrupación de lotes, precintos y QR maestro.
3. Viajes con lotes completos, aviso de guía ERP y despacho.
4. Recepción, discrepancias, fotografías y consulta de trazabilidad.
5. Sincronización offline y validación de la APK en dispositivos Android.

## Pendientes de integración

Se recibió la URL de Supabase y su clave pública por un canal separado; no se incluyen aquí. Falta conocer el nombre y las columnas de la tabla de bienes y un ejemplo del contenido de un QR existente.

Revisar el esquema existente antes de preparar migraciones. Conservar los datos, tablas y usuarios actuales.
