import '../models/smoke_context.dart';
import 'risk_assessment.dart';

/// Um cuidado sugerido a partir do contexto, com as referências em que se apoia
/// (números de `references` em `data/references.dart`). Lista vazia = critério do projeto.
class ContextTip {
  const ContextTip(this.text, this.refs, {this.urgent = false});

  final String text;
  final List<int> refs;

  /// Destaca o item (procurar atendimento).
  final bool urgent;
}

/// Cuidados extras conforme o contexto. NÃO altera os pontos nem o nível de risco.
List<ContextTip> contextTips(SmokeContext c, Profile profile) {
  final chronic = profile.chronicRespiratory || profile.chronicCardiac;
  final tips = <ContextTip>[];

  if (c.medsNotWorking == true) {
    tips.add(const ContextTip(
      'Sua medicação habitual não está aliviando: procure atendimento médico agora '
      '(UPA, pronto-socorro) ou ligue 192. Não espere piorar.',
      [],
      urgent: true,
    ));
  }
  if (c.worsening == true) {
    tips.add(const ContextTip(
      'Se os sintomas estão piorando, procure atendimento. Quem tem asma, DPOC ou doença '
      'do coração deve fazê-lo mais cedo.',
      [1],
      urgent: true,
    ));
  }
  if (c.place == Place.homeOpen) {
    tips.add(const ContextTip(
      'Feche janelas e portas para reduzir a entrada de fumaça.',
      [1],
    ));
  }
  if (c.place == Place.outdoors && c.visibleSmoke == true) {
    tips.add(const ContextTip(
      'Com fumaça visível, vá para um ambiente fechado assim que possível. Se precisar '
      'ficar fora, use respirador PFF2/N95 bem ajustado ao rosto.',
      [1, 2],
    ));
  }
  if ((c.mask == MaskUse.surgicalOrCloth) &&
      (c.visibleSmoke == true || c.place == Place.outdoors)) {
    tips.add(const ContextTip(
      'Máscara cirúrgica não é recomendada contra fumaça (EPA). Não encontramos nas fontes '
      'lidas recomendação para máscara de pano comum. Por cautela, prefira PFF2/N95 bem '
      'ajustada ao rosto.',
      [2],
    ));
  }
  if (c.mask == MaskUse.none && c.visibleSmoke == true && c.place == Place.outdoors) {
    tips.add(const ContextTip(
      'Se você precisa sair em meio à fumaça, um respirador PFF2/N95 bem ajustado reduz a '
      'inalação de partículas. Eles não são feitos para crianças.',
      [1, 2],
    ));
  }
  if (c.outdoorExercise == true) {
    tips.add(const ContextTip(
      'Reduza atividades físicas intensas ao ar livre enquanto houver fumaça.',
      [2],
    ));
  }
  if (c.outdoorWork == true) {
    tips.add(const ContextTip(
      'Trabalhadores ao ar livre estão entre os mais expostos: sempre que possível, faça '
      'pausas em local fechado e reduza o tempo na fumaça.',
      [2],
    ));
  }
  if (c.cleanAir == false && (c.visibleSmoke == true || c.place != null)) {
    tips.add(const ContextTip(
      'Sem ambiente com ar filtrado, escolha um cômodo da casa para ficar, com portas e '
      'janelas fechadas. Se usar purificador de ar, prefira um que emita pouco ou nenhum ozônio.',
      [1, 2],
    ));
  }
  if (c.medsAtHand == false && chronic) {
    tips.add(const ContextTip(
      'Mantenha à mão a medicação indicada pelo seu médico e converse com ele ou com a '
      'unidade de saúde sobre um plano para dias de fumaça.',
      [1],
    ));
  }
  if (c.immune == true) {
    tips.add(const ContextTip(
      'Com imunidade reduzida, converse com seu médico sobre cuidados adicionais em dias de fumaça. '
      '(Cuidado incluído pelo projeto; não consta nos trechos lidos das fontes.)',
      [],
    ));
  }
  return tips;
}
