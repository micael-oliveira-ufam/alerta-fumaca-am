/// Famílias de satélites de detecção de focos de calor usadas no app.
///
/// Os nomes em [inpeNames] são os valores EXATOS do campo `satelite` nas camadas
/// `*_br_todosats` do INPE (TerraBrasilis). Foram conferidos por contagem direta
/// no servidor (janela de 48 h, Brasil): AQUA_M-T, TERRA_M-T, NOAA-20, NOAA-21,
/// NPP-375 e NPP-375D. O significado do sufixo "D" em NPP-375D não foi confirmado
/// em documentação; por isso as duas variantes são agrupadas como "Suomi NPP".
///
/// Satélites geoestacionários (GOES, MSG) existem na camada, mas ficam fora do
/// app por não terem sido pedidos e por gerarem muitas detecções de baixa confiança.
enum FireSatellite {
  modis('MODIS · Aqua e Terra', 'MODIS', ['AQUA_M-T', 'TERRA_M-T'], true),
  noaa20('NOAA-20 · VIIRS', 'NOAA-20', ['NOAA-20'], true),
  suomi('Suomi NPP · VIIRS', 'Suomi NPP', ['NPP-375', 'NPP-375D'], true),
  noaa21('NOAA-21 · VIIRS', 'NOAA-21', ['NOAA-21'], false);

  const FireSatellite(this.label, this.shortLabel, this.inpeNames, this.defaultSelected);

  /// Nome completo, para chips e legendas.
  final String label;

  /// Nome curto, para resumos.
  final String shortLabel;

  /// Valores do campo `satelite` do INPE que pertencem a esta família.
  final List<String> inpeNames;

  /// Se já vem marcado ao abrir o mapa.
  final bool defaultSelected;

  /// Família de um valor do campo `satelite`, ou `null` se não for uma das suportadas.
  static FireSatellite? fromInpeName(String name) {
    for (final satellite in values) {
      if (satellite.inpeNames.contains(name)) return satellite;
    }
    return null;
  }

  /// Seleção inicial (MODIS, NOAA-20 e Suomi NPP).
  static Set<FireSatellite> defaults() => {
        for (final satellite in values)
          if (satellite.defaultSelected) satellite,
      };

  /// Nomes do INPE das famílias escolhidas, sem repetição e ordenados
  /// (ordem estável: o mesmo conjunto gera sempre a mesma consulta).
  static List<String> inpeNamesOf(Iterable<FireSatellite> satellites) {
    final names = <String>{
      for (final satellite in satellites) ...satellite.inpeNames,
    };
    return names.toList()..sort();
  }
}
