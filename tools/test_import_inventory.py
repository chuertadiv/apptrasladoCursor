import unittest
from datetime import datetime
from import_inventory import CODE, DATE, sent_at, select_latest, photo_refs


class ImportTests(unittest.TestCase):
    def row(self, code, date, name='Bien'):
        return {CODE: code, DATE: date, 'Nombre': name}

    def test_latest_is_date_not_row_order(self):
        rows = [(2, self.row('00001', '22 oct 2026, 04:50 p. m.')),
                (3, self.row('00001', '21 oct 2026, 11:55 p. m.'))]
        selected, errors, count = select_latest(rows)
        self.assertEqual((selected[0][0], selected[0][1], count, errors), ('00001', 2, 1, []))

    def test_midnight_noon_and_excel_date(self):
        self.assertEqual(sent_at('22 oct 2026, 12:00 a. m.').hour, 0)
        self.assertEqual(sent_at('22 oct 2026, 12:00 p. m.').hour, 12)
        date = datetime(2026, 10, 22, 8)
        self.assertEqual(sent_at(date), date)

    def test_month_order_not_text(self):
        selected, errors, _ = select_latest([(2, self.row('A', '30 sep 2026, 01:00 p. m.')),
                                            (3, self.row('A', '1 oct 2026, 01:00 p. m.'))])
        self.assertEqual(selected[0][1], 3)
        self.assertFalse(errors)
        self.assertEqual(sent_at('30 sept 2026, 04:25 p. m.'), datetime(2026, 9, 30, 16, 25))

    def test_tie_with_conflicting_records_is_blocked(self):
        selected, errors, _ = select_latest([(2, self.row('A', '22 oct 2026, 01:00 p. m.', 'Uno')),
                                            (3, self.row('A', '22 oct 2026, 01:00 p. m.', 'Dos'))])
        self.assertFalse(selected)
        self.assertEqual(len(errors), 1)

    def test_invalid_date_does_not_hide_older_row(self):
        selected, errors, _ = select_latest([(2, self.row('A', None)),
                                            (3, self.row('A', '22 oct 2026, 01:00 p. m.'))])
        self.assertFalse(selected)
        self.assertEqual(len(errors), 1)

    def test_numeric_identifier_rejected(self):
        selected, errors, _ = select_latest([(2, self.row(123, datetime(2026, 10, 22)))])
        self.assertFalse(selected)
        self.assertTrue(errors)

    def test_photo_json_validation(self):
        self.assertEqual(photo_refs('["https://example.com/photo.jpg"]'), ['https://example.com/photo.jpg'])
        with self.assertRaises(ValueError):
            photo_refs('{"url":"https://example.com"}')


if __name__ == '__main__':
    unittest.main()

