/// Onde a pessoa está agora.
enum Place {
  outdoors('ar_livre', 'Ao ar livre', 'Rua, quintal, barco, roça'),
  homeOpen('casa_janelas_abertas', 'Dentro, janelas abertas', 'Em casa ou no trabalho'),
  homeClosed('casa_janelas_fechadas', 'Dentro, janelas fechadas', 'Em casa ou no trabalho');

  const Place(this.wire, this.label, this.hint);

  /// Valor aceito pela API (`contexto.local`).
  final String wire;
  final String label;
  final String hint;
}

/// Proteção respiratória usada ao sair hoje.
enum MaskUse {
  didNotGoOut('nao_saiu', 'Não saí'),
  none('nao', 'Sem máscara'),
  surgicalOrCloth('cirurgica_pano', 'Cirúrgica ou pano'),
  respirator('pff2_n95', 'PFF2 / N95');

  const MaskUse(this.wire, this.label);

  /// Valor aceito pela API (`contexto.mascara`).
  final String wire;
  final String label;
}

/// Respostas de contexto do questionário. Todas são opcionais: `null` significa
/// "não sei / prefiro não responder" e nesse caso o campo não é enviado ao servidor.
///
/// Essas respostas NÃO entram no cálculo de pontos (`assess`); servem para orientar
/// cuidados e para as estatísticas agregadas.
class SmokeContext {
  const SmokeContext({
    this.place,
    this.visibleSmoke,
    this.mask,
    this.outdoorExercise,
    this.cleanAir,
    this.outdoorWork,
    this.immune,
    this.medsAtHand,
    this.medsNotWorking,
    this.worsening,
  });

  final Place? place;
  final bool? visibleSmoke;
  final MaskUse? mask;

  /// Fez atividade física intensa ao ar livre hoje.
  final bool? outdoorExercise;

  /// Tem um ambiente com ar filtrado/climatizado ou cômodo protegido para ficar.
  final bool? cleanAir;

  /// Trabalha ao ar livre.
  final bool? outdoorWork;

  /// Tem doença ou usa remédio que reduz a imunidade.
  final bool? immune;

  /// Tem à mão a medicação de uso contínuo ou de resgate (se usa alguma).
  final bool? medsAtHand;

  /// A medicação habitual não está aliviando os sintomas.
  final bool? medsNotWorking;

  /// Os sintomas estão piorando.
  final bool? worsening;

  /// `true` se nenhuma pergunta de contexto foi respondida.
  bool get isEmpty => toPayload().isEmpty;

  /// Campos no formato da API (`contexto`); só inclui o que foi respondido.
  Map<String, dynamic> toPayload() => {
        if (place != null) 'local': place!.wire,
        if (visibleSmoke != null) 'fumaca_visivel': visibleSmoke,
        if (mask != null) 'mascara': mask!.wire,
        if (outdoorExercise != null) 'atividade_fisica_ar_livre': outdoorExercise,
        if (cleanAir != null) 'ar_filtrado': cleanAir,
        if (outdoorWork != null) 'trabalho_ar_livre': outdoorWork,
        if (immune != null) 'imunologica': immune,
        if (medsAtHand != null) 'medicacao_a_mao': medsAtHand,
        if (medsNotWorking != null) 'medicacao_nao_alivia': medsNotWorking,
        if (worsening != null) 'piorando': worsening,
      };
}
