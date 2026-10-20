"""Testes de tool/apply_platform_config.py (sem Flutter).

Rodar na raiz do projeto:  python3 tool/test_apply_platform_config.py -v
"""

import sys
import unittest
import xml.dom.minidom as minidom
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from apply_platform_config import patch_manifest, patch_plist  # noqa: E402

# Modelo equivalente ao gerado por `flutter create` (com o <queries> padrão).
MANIFEST_WITH_QUERIES = """<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="x" android:name="${applicationName}">
        <activity android:name=".MainActivity" android:exported="true"/>
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
"""

MANIFEST_NO_QUERIES = """<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="x"/>
</manifest>
"""

PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>x</string>
</dict>
</plist>
"""

PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
]


class ManifestTests(unittest.TestCase):
    def check_manifest(self, source: str) -> str:
        patched, added = patch_manifest(source)
        self.assertEqual(len(added), 5)  # 3 permissões + queries/DIAL + nome do app
        self.assertIn('android:label="Alerta Fumaça AM"', patched)
        self.assertEqual(patched.count("android:label="), 1)
        for p in PERMISSIONS:
            self.assertEqual(patched.count(f'android:name="{p}"'), 1, p)
        self.assertEqual(patched.count("android.intent.action.DIAL"), 1)
        self.assertEqual(patched.count("<queries>"), 1)
        minidom.parseString(patched)  # continua XML válido
        return patched

    def test_with_existing_queries_keeps_process_text(self):
        patched = self.check_manifest(MANIFEST_WITH_QUERIES)
        self.assertIn("PROCESS_TEXT", patched)

    def test_without_queries(self):
        self.check_manifest(MANIFEST_NO_QUERIES)

    def test_idempotent(self):
        once, _ = patch_manifest(MANIFEST_WITH_QUERIES)
        twice, added = patch_manifest(once)
        self.assertEqual(added, [])
        self.assertEqual(once, twice)

    def test_only_missing_permissions_are_added(self):
        partial = MANIFEST_NO_QUERIES.replace(
            "<application",
            '<uses-permission android:name="android.permission.INTERNET"/><application',
        )
        patched, added = patch_manifest(partial)
        self.assertNotIn("android.permission.INTERNET", added)
        self.assertEqual(patched.count('android:name="android.permission.INTERNET"'), 1)


    def test_nome_do_template_com_underscores_e_trocado(self):
        template = MANIFEST_NO_QUERIES.replace('android:label="x"', 'android:label="alerta_fumaca_am"')
        patched, _ = patch_manifest(template)
        self.assertNotIn("alerta_fumaca_am", patched)
        self.assertIn('android:label="Alerta Fumaça AM"', patched)

    def test_application_sem_label_recebe_o_nome(self):
        patched, added = patch_manifest(MANIFEST_NO_QUERIES.replace(' android:label="x"', ""))
        self.assertIn('android:label="Alerta Fumaça AM"', patched)
        minidom.parseString(patched)


class PlistTests(unittest.TestCase):
    def test_nomes_exibidos(self):
        template = PLIST.replace(
            "<key>CFBundleName</key>\n\t<string>x</string>",
            "<key>CFBundleDisplayName</key>\n\t<string>Alerta Fumaca Am</string>\n"
            "\t<key>CFBundleName</key>\n\t<string>alerta_fumaca_am</string>",
        )
        patched, _ = patch_plist(template)
        self.assertEqual(patched.count("Alerta Fumaça AM"), 2)
        self.assertNotIn("alerta_fumaca_am", patched)
        self.assertNotIn("Alerta Fumaca Am", patched)
        minidom.parseString(patched)

    def test_adds_keys_once(self):
        patched, added = patch_plist(PLIST)
        self.assertEqual(
            added,
            [
                "NSLocationWhenInUseUsageDescription",
                "LSApplicationQueriesSchemes",
                "CFBundleDisplayName=Alerta Fumaça AM",
                "CFBundleName=Alerta Fumaça AM",
            ],
        )
        minidom.parseString(patched)
        again, added_again = patch_plist(patched)
        self.assertEqual(added_again, [])
        self.assertEqual(patched, again)


if __name__ == "__main__":
    unittest.main()
