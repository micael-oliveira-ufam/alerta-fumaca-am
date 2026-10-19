"""Limitador simples de envios por origem (janela fixa de 1 minuto, em memória).

Não persiste nada: o endereço de origem existe apenas em memória durante o
minuto corrente e nunca é gravado no banco. Atrás de um proxy reverso, todas as
requisições podem parecer vir do mesmo endereço; nesse caso configure o limite
no próprio proxy (ex.: Nginx `limit_req`) e use RATE_LIMIT_PER_MIN=0 aqui.
"""

from __future__ import annotations

import time
from typing import Callable


class RateLimiter:
    def __init__(
        self,
        limit: int,
        window_s: int = 60,
        clock: Callable[[], float] = time.monotonic,
        max_keys: int = 10_000,
    ) -> None:
        self.limit = limit
        self.window_s = window_s
        self._clock = clock
        self._max_keys = max_keys
        self._hits: dict[str, tuple[float, int]] = {}

    def allow(self, key: str) -> bool:
        if self.limit <= 0:
            return True
        now = self._clock()
        start, count = self._hits.get(key, (now, 0))
        if now - start >= self.window_s:
            start, count = now, 0
        if count >= self.limit:
            self._hits[key] = (start, count)
            return False
        self._hits[key] = (start, count + 1)
        if len(self._hits) > self._max_keys:
            self._purge(now)
        return True

    def _purge(self, now: float) -> None:
        self._hits = {
            k: (s, c) for k, (s, c) in self._hits.items() if now - s < self.window_s
        }
