/* Aviso de nova versão da página: quem deixa a aba aberta não fica com código antigo.
   Consulta /publico/versao; se o "build" mudar em relação ao da carga, mostra um aviso para recarregar.
   Nunca recarrega sozinho (não perde o que a pessoa está lendo). */
(function () {
  'use strict';
  var INTERVALO_MS = 5 * 60 * 1000;
  var inicial = null;
  var avisado = false;

  function aviso() {
    if (avisado) return;
    avisado = true;
    var d = document.createElement('div');
    d.className = 'atualizar';
    d.setAttribute('role', 'status');
    var t = document.createElement('span');
    t.textContent = 'Há uma nova versão deste painel.';
    var b = document.createElement('button');
    b.type = 'button';
    b.textContent = 'Atualizar agora';
    b.addEventListener('click', function () { location.reload(); });
    d.appendChild(t);
    d.appendChild(b);
    document.body.appendChild(d);
  }

  function checar() {
    fetch('/publico/versao', { cache: 'no-store' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (j) {
        if (!j || !j.build) return;
        var v = document.getElementById('versao-servidor');
        if (v && j.servidor) v.textContent = 'servidor v' + j.servidor;
        if (inicial === null) inicial = j.build;
        else if (j.build !== inicial) aviso();
      })
      .catch(function () { /* sem rede: tenta de novo no próximo ciclo */ });
  }

  checar();
  setInterval(checar, INTERVALO_MS);
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) checar();
  });
})();
