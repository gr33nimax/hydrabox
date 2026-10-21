from pathlib import Path
import unittest
from xml.etree import ElementTree

class ResourceTest(unittest.TestCase):
    def test_localizations_have_unique_keys(self):
        root = Path(__file__).resolve().parents[2]
        for path in (root / 'ui/app/src/commonMain/composeResources').glob('*/strings.xml'):
            names = [element.attrib['name'] for element in ElementTree.parse(path).getroot()]
            self.assertEqual(len(names), len(set(names)), str(path))
