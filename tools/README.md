# Preparación local del inventario

Python 3.11 o superior. No conecta con Supabase ni modifica el archivo Excel original.

```sh
python -m pip install -r tools/requirements.txt
python -m unittest discover -s tools -p 'test_*.py' -v
python tools/import_inventory.py "inventario.xlsx" --salida inventario-local
```

Selecciona el registro con mayor fecha Enviado por Código de Censo de Inventario. Admite fechas Excel y el formato español del archivo (incluye sep y sept; hora a. m./p. m.). Mantiene códigos como texto, distingue mayúsculas/minúsculas y no elimina ceros iniciales. Si Excel almacenó un código como número, lo rechaza para no asumir que puede recuperar ceros perdidos.

Produce una carpeta por SHA256 del archivo. No sobrescribe resultados previos: para repetir una ejecución usar otro directorio de salida. resumen.json contiene cantidades y problemas. Solo si todas las filas pasan la validación produce inventario-preparado.json con los registros originales y el padrón seleccionado. Este archivo contiene información interna: mantenerlo fuera de GitHub.

Fechas inválidas o registros distintos empatados en la fecha más reciente requieren revisión. El proceso retorna 2 en ese caso y no produce un padrón parcial. El archivo definitivo se espera sin duplicados; se conserva el control como validación.

Los datos preparados se alinean con la migración de traslado, pero no son un script de carga directa: aún falta ejecutar las migraciones y desarrollar la importación transaccional autorizada que asigne creado_por al lote de importación. Esta herramienta solo prepara los datos.

## Validación realizada

- 7 pruebas unitarias correctas: selección por fecha aunque cambie el orden de filas, cambio de mes, medianoche/mediodía, identificadores con ceros, códigos numéricos, empates, fecha inválida y referencias de fotografías.
- Ejecución sobre la muestra: 7.913 filas, 7.430 códigos distintos; 7.427 candidatos y 3 códigos bloqueados por empates entre registros diferentes en la fecha más reciente.
- No se importaron datos ni se crearon tablas en Supabase. No se publicaron registros reales.
