"""Prepare inventory JSON locally; never connects to or changes Supabase."""
import argparse
from collections import defaultdict
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import unicodedata
from uuid import NAMESPACE_URL, uuid5

CODE = 'Código de Censo de Inventario'
DATE = 'Enviado'
MAPPING = {
    'Nombre': 'nombre', 'Ubicación de Inventario': 'ubicacion_origen',
    'Código de Inventario Activo Fijo': 'codigo_activo_fijo',
    'Código Alternativo': 'codigo_alternativo',
    'Estado físico / funcional': 'estado_fisico_origen',
    'Estado de las etiquetas': 'estado_etiquetas',
}
MONTHS = dict(zip(('ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'), range(1, 13)))
MONTHS['sept'] = 9


def sent_at(value):
    """Parse Excel datetimes or the Spanish export's local wall-clock format."""
    if isinstance(value, datetime):
        if value.tzinfo is not None:
            raise ValueError('Fecha con zona horaria no admitida en este formato')
        return value
    if not isinstance(value, str):
        raise ValueError('Fecha Enviado vacía o inválida')
    text = ''.join(c for c in unicodedata.normalize('NFD', value.lower()) if not unicodedata.combining(c))
    text = re.sub(r'[\s\u00a0\u202f]+', ' ', text).strip()
    match = re.fullmatch(r'(\d{1,2}) ([a-z]{3,4})\.? (\d{4}),? (\d{1,2}):(\d{2})(?::(\d{2}))?\s*([ap])\.?\s*m\.?', text)
    if not match:
        raise ValueError('Formato Enviado no reconocido')
    day, month, year, hour, minute, second, period = match.groups()
    if month not in MONTHS or not 1 <= int(hour) <= 12:
        raise ValueError('Mes u hora inválidos')
    hour = int(hour) % 12 + (12 if period == 'p' else 0)
    return datetime(int(year), MONTHS[month], int(day), hour, int(minute), int(second or 0))


def select_latest(rows):
    groups, errors = defaultdict(list), []
    for number, raw in rows:
        value = raw.get(CODE)
        if not isinstance(value, str) or value.strip().lower() in ('', 'sin información', 'sin informacion'):
            errors.append({'fila': number, 'motivo': 'Código de censo ausente o no textual'})
            continue
        groups[value.strip()].append((number, raw))
    selected = []
    for code, records in groups.items():
        try:
            dated = [(sent_at(raw.get(DATE)), number, raw) for number, raw in records]
        except ValueError as exc:
            errors.append({'codigo_censo': code, 'filas': [n for n, _ in records], 'motivo': str(exc)})
            continue
        latest = max(item[0] for item in dated)
        winners = [(number, raw) for date, number, raw in dated if date == latest]
        # Different records at the same timestamp need human review.
        if len(winners) > 1 and any(raw != winners[0][1] for _, raw in winners[1:]):
            errors.append({'codigo_censo': code, 'filas': [n for n, _ in winners], 'motivo': 'Empate entre registros diferentes'})
            continue
        number, raw = winners[0]
        selected.append((code, number, raw))
    return selected, errors, len(groups)


def photo_refs(value):
    if value in (None, '', 'Sin información'):
        return []
    refs = json.loads(value) if isinstance(value, str) else value
    if not isinstance(refs, list) or any(not isinstance(x, str) or not x.startswith('https://') for x in refs):
        raise ValueError('Fotografías: se esperaba una lista JSON de URL HTTPS')
    return refs


def read_rows(path, sheet):
    import openpyxl
    workbook = openpyxl.load_workbook(path, read_only=True, data_only=False)
    try:
        worksheet = workbook[sheet]
        iterator = worksheet.iter_rows()
        headers = [cell.value for cell in next(iterator)]
        required = [CODE, DATE, *MAPPING, 'Foto del bien', 'Foto etiqueta fabricante / Serial']
        if any(headers.count(name) != 1 for name in required):
            raise ValueError('Faltan columnas requeridas o hay encabezados duplicados')
        result = []
        for number, cells in enumerate(iterator, 2):
            if not any(cell.value is not None for cell in cells):
                continue
            if any(cell.data_type == 'f' for cell in cells):
                raise ValueError(f'Fila {number}: se requieren valores, no fórmulas')
            result.append((number, dict(zip(headers, (cell.value for cell in cells)))))
        return result
    finally:
        workbook.close()


def prepare(path, output, sheet='Respuestas'):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    rows = read_rows(path, sheet)
    chosen, errors, distinct = select_latest(rows)
    import_id = str(uuid5(NAMESPACE_URL, 'traslado:import:' + digest))
    def source_id(number):
        return str(uuid5(NAMESPACE_URL, f'traslado:{digest}:{sheet}:{number}'))
    goods = []
    for code, number, raw in chosen:
        try:
            if not isinstance(raw.get('Nombre'), str) or not raw['Nombre'].strip():
                raise ValueError('Nombre vacío')
            good = {field: (str(raw[column]) if raw[column] is not None else None) for column, field in MAPPING.items()}
            good.update(codigo_censo=code, fuente_historial_id=source_id(number),
                        fotos_bien=photo_refs(raw.get('Foto del bien')),
                        fotos_serial=photo_refs(raw.get('Foto etiqueta fabricante / Serial')))
            goods.append(good)
        except (ValueError, TypeError) as exc:
            errors.append({'codigo_censo': code, 'fila': number, 'motivo': str(exc)})
    summary = {'estado': 'requiere_revision' if errors else 'preparado', 'filas_fuente': len(rows),
               'codigos_distintos': distinct, 'bienes_preparados': len(goods),
               'filas_adicionales_mismo_codigo': len(rows) - distinct,
               'problemas': errors, 'archivo_sha256': digest,
               'regla': 'Mayor fecha Enviado por código; no usar orden de filas',
               'nota': 'Preparación local. Sin importación ni cambios en Supabase.'}
    output.mkdir(parents=True, exist_ok=True)
    target = output / digest
    target.mkdir(exist_ok=False)
    payload = {'importacion': {'id': import_id, 'archivo_nombre': path.name, 'archivo_sha256': digest},
               'inventario_historial': [{'id': source_id(n), 'importacion_id': import_id, 'hoja': sheet,
                   'fila_excel': n, 'codigo_censo': str(raw.get(CODE) or '').strip(), 'datos_originales': raw} for n, raw in rows],
               'bienes': goods}
    (target / 'resumen.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    # Fail closed: never emit a partially importable inventory.
    if not errors:
        (target / 'inventario-preparado.json').write_text(json.dumps(payload, ensure_ascii=False, default=str), encoding='utf-8')
    return summary, target


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archivo', type=Path)
    parser.add_argument('--salida', type=Path, required=True)
    parser.add_argument('--hoja', default='Respuestas')
    args = parser.parse_args()
    report, folder = prepare(args.archivo, args.salida, args.hoja)
    print(json.dumps({**{k: v for k, v in report.items() if k != 'problemas'},
                      'cantidad_problemas': len(report['problemas']), 'carpeta': str(folder)}, ensure_ascii=False, indent=2))
    raise SystemExit(2 if report['problemas'] else 0)

