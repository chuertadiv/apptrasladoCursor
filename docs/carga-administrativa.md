# Carga administrativa de inventario

La migración 20261022234155_importacion_administrativa_inventario está aplicada. Agrega la RPC public.traslado_importar_inventario(p_datos jsonb) y políticas de inserción para administradores. No requiere clave service_role en el cliente.

## Flujo

1. Preparar el Excel con tools/import_inventory.py.
2. Iniciar sesión con un usuario que tenga rol administrador en traslado.usuario_roles.
3. Enviar el contenido de inventario-preparado.json como p_datos mediante supabase.rpc('traslado_importar_inventario', { p_datos: datos }).
4. Mostrar el resultado confirmado por el servidor. No presentar una carga como exitosa antes de recibir respuesta.

La función solo acepta archivos preparados sin errores, con al menos un bien y hasta 20.000 registros fuente por solicitud. Verifica SHA256 de formato válido, fuente de cada bien dentro del mismo lote de importación, unicidad de códigos seleccionados y cobertura de todos los códigos del historial. El nombre y estado del bien provienen de la selección del preparador; el administrador es responsable de usar el preparador validado para elegir la fecha más reciente. El servidor no recibe el Excel binario y no recalcula su hash ni interpreta sus fechas.

Una solicitud se guarda de forma atómica. Un error revierte importación, historial y bienes. El SHA256 y un bloqueo transaccional serializan reintentos del mismo archivo. La respuesta ya_importado indica que ese hash ya se registró; no se insertan bienes nuevos. El autor se toma de auth.uid(), ignorando identificadores de autor enviados por el cliente.

Es una carga inicial aditiva. Otro archivo con códigos existentes falla y no sobrescribe bienes ni su trazabilidad. Una actualización del padrón requerirá un flujo aparte.

## Permisos

SECURITY INVOKER, search_path vacío y autorización basada en la tabla de roles. Solo administrador puede insertar importaciones, historial y bienes. Los operadores conservan lectura de bienes sin acceso al historial administrativo. No se conceden UPDATE ni DELETE.

## Verificación ejecutada

Pruebas PostgreSQL con datos sintéticos y rollback: carga válida, autor correcto, reintento sin duplicados, conflicto que revierte también la cabecera, selección repetida rechazada, bloqueo de operador por RPC y por tabla, aislamiento del historial y bloqueo anónimo. No quedaron usuarios ni bienes de prueba.

No se han cargado datos reales. La cuenta administradora indicada por el usuario aún debe existir en Supabase Auth para asignarle el rol. No publicar correos personales o contraseñas en el repositorio.
