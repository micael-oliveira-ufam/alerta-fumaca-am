"""Contrato do domínio fixo: compose, .env.example e URL padrão dos scripts de compilação.

Rodar:  python3 -m pytest -q tool/test_dominio.py   (ou python3 tool/test_dominio.py)
"""
import subprocess
import unittest
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
DOMINIO = "https://respira-amazonas.cloud"


def _bash(trecho: str) -> str:
    r = subprocess.run(["bash", "-c", trecho], cwd=RAIZ, capture_output=True, text=True, check=True)
    return r.stdout


class DominioFixo(unittest.TestCase):
    def test_url_padrao_e_o_dominio(self):
        self.assertEqual(_bash("source tool/_ambiente.sh; resolver_url_servidor ''"), DOMINIO)

    def test_url_explicita_prevalece(self):
        self.assertEqual(
            _bash("source tool/_ambiente.sh; resolver_url_servidor https://x.trycloudflare.com"),
            "https://x.trycloudflare.com",
        )

    def test_local_desliga_o_servidor(self):
        self.assertEqual(_bash("source tool/_ambiente.sh; resolver_url_servidor --local"), "")

    def test_url_padrao_pode_ser_trocada_por_variavel(self):
        out = _bash("URL_SERVIDOR_PADRAO=https://outro.exemplo; source tool/_ambiente.sh; resolver_url_servidor ''")
        self.assertEqual(out, "https://outro.exemplo")

    def test_compose_tem_o_tunel_nomeado(self):
        txt = (RAIZ / "docker-compose.yml").read_text(encoding="utf-8")
        self.assertIn("tunnel_dominio:", txt)
        self.assertIn('profiles: ["dominio"]', txt)
        self.assertIn("TUNNEL_TOKEN: ${TUNNEL_TOKEN:-}", txt)
        # forma documentada pela Cloudflare: --no-autoupdate entre "tunnel" e "run"; token por variável
        self.assertIn('command: ["tunnel", "--no-autoupdate", "run"]', txt)

    def test_env_example_nao_traz_token(self):
        linhas = (RAIZ / ".env.example").read_text(encoding="utf-8").splitlines()
        self.assertIn("TUNNEL_TOKEN=", linhas)  # vazio: o token é segredo e nunca vai ao Git

    def test_scripts_de_compilacao_usam_o_resolvedor(self):
        for nome in ("gerar_apk.sh", "gerar_ios.sh", "abrir_emulador.sh"):
            txt = (RAIZ / "tool" / nome).read_text(encoding="utf-8")
            self.assertIn("resolver_url_servidor", txt, nome)


if __name__ == "__main__":
    unittest.main()
