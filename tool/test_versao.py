"""Testes do tool/versao.py. Rode: python3 tool/test_versao.py"""

import importlib.util
import shutil
import tempfile
import unittest
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("versao", RAIZ / "tool" / "versao.py")
versao = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(versao)

ARQUIVOS = ["VERSION", "pubspec.yaml", "CHANGELOG.md", "lib/data/app_info.dart", "server/app/main.py"]


class SemVer(unittest.TestCase):
    def test_incrementos(self):
        self.assertEqual(versao.proxima("1.1.0", "patch"), "1.1.1")
        self.assertEqual(versao.proxima("1.1.9", "patch"), "1.1.10")
        self.assertEqual(versao.proxima("1.1.4", "minor"), "1.2.0")
        self.assertEqual(versao.proxima("1.9.4", "major"), "2.0.0")

    def test_tipo_invalido(self):
        with self.assertRaises(versao.ErroVersao):
            versao.proxima("1.0.0", "huge")

    def test_formato(self):
        self.assertIsNotNone(versao.SEMVER.match("0.0.1"))
        for ruim in ["1.0", "1.0.0.0", "v1.0.0", "01.0.0", "1.0.0-beta"]:
            self.assertIsNone(versao.SEMVER.match(ruim), ruim)


class Repositorio(unittest.TestCase):
    def test_versao_do_repositorio_esta_consistente(self):
        # Falha aqui se alguém mudar uma cópia sem rodar `sincronizar`/`nova`.
        self.assertEqual(versao.problemas(versao.ler_versao()), [])


class Sincronia(unittest.TestCase):
    """Roda `nova` e `sincronizar` numa cópia dos arquivos de versão, nunca no repositório."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        for rel in ARQUIVOS:
            destino = self.tmp / rel
            destino.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(RAIZ / rel, destino)
        self._raiz_original = versao.RAIZ
        versao.RAIZ = self.tmp

    def tearDown(self):
        versao.RAIZ = self._raiz_original
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_nova_sobe_as_copias_build_e_changelog(self):
        atual = versao.ler_versao()
        (self.tmp / "CHANGELOG.md").write_text(
            (self.tmp / "CHANGELOG.md").read_text(encoding="utf-8").replace(
                "Nenhuma mudança desde a", "- Item de teste.\n\nNenhuma mudança desde a"
            ),
            encoding="utf-8",
        )
        nova = versao.proxima(atual, "minor")
        (self.tmp / "VERSION").write_text(nova + "\n", encoding="utf-8")
        versao.sincronizar(nova, 3)
        versao.mover_changelog(nova, "2026-12-01")

        self.assertEqual(versao.versoes_das_copias()["pubspec.yaml"], nova)
        self.assertIn(f"version: {nova}+3", (self.tmp / "pubspec.yaml").read_text(encoding="utf-8"))
        self.assertEqual(versao.problemas(nova), [])
        texto = (self.tmp / "CHANGELOG.md").read_text(encoding="utf-8")
        self.assertIn(f"## [{nova}] - 2026-12-01", texto)
        self.assertIn("- Item de teste.", texto)  # o conteúdo do não lançado foi preservado

    def test_divergencia_e_detectada(self):
        texto = (self.tmp / "lib/data/app_info.dart").read_text(encoding="utf-8")
        (self.tmp / "lib/data/app_info.dart").write_text(
            texto.replace(f"kAppVersion = '{versao.ler_versao()}'", "kAppVersion = '9.9.9'"),
            encoding="utf-8",
        )
        erros = versao.problemas(versao.ler_versao())
        self.assertTrue(any("app_info.dart" in e for e in erros))

    def test_secao_repetida_e_recusada(self):
        with self.assertRaises(versao.ErroVersao):
            versao.mover_changelog(versao.ler_versao(), "2026-12-01")


if __name__ == "__main__":
    unittest.main()
