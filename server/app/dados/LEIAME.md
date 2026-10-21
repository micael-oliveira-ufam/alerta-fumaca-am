# Municípios do Amazonas (62)

`municipios_am.csv`: código IBGE, nome, latitude e longitude dos 62 municípios do Amazonas
(código de UF 13).

**Procedência:** extraído de `csv/municipios.csv` do repositório
<https://github.com/kelvins/municipios-brasileiros> (licença MIT, © 2016 Kelvin S. do Prado),
commit `503e2f70bbf1b4b7ec0b1f68b09086ccc38fe861` (10/12/2025). O repositório descreve o
conteúdo como código IBGE, nome e coordenadas dos municípios; **não informa se a coordenada é
da sede ou do centroide**. Usada só para consultar o modelo de qualidade do ar, cuja célula tem
~45 km, uma diferença de poucos quilômetros não altera o resultado. Não use para outra finalidade
sem conferir com a malha do IBGE.

Para reproduzir: `git clone https://github.com/kelvins/municipios-brasileiros`, filtrar
`codigo_uf == 13`, manter as 4 colunas e ordenar por nome.
