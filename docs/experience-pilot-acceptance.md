# Avaliação do piloto de experiência

Ambiente confirmado pelo responsável: testes, produto ainda não lançado.
Distribuição escolhida: APK para instalação direta.

## APK e dados

O APK `Tatuzin Piloto` usa o pacote `br.com.tatuzin.gestao.pilot`, certificado
Android de testes e compilação release sem depuração. Pode coexistir com Tatuzin.
O banco local é separado pelo pacote; entrar na mesma empresa acessa os dados
remotos dessa empresa. Use somente operações autorizadas no ambiente de testes.
O APK não é uma versão para Google Play. A assinatura definitiva continua exigida
para o pacote oficial. Se a chave de teste do CI mudar, será necessário reinstalar
o piloto: sincronize antes e não desinstale com operações locais pendentes.

## Cinco sessões observadas

Escolher cinco pessoas reais que operam ou operarão o PDV. Registrar IDs internos
O1–O5, sem nomes, e-mail, senha ou dados de clientes. Cada pessoa realiza uma
sessão na versão anterior e outra no piloto, no mesmo aparelho, após uma tentativa
de familiarização. As operações são dados de teste autorizados e não comprovam
uso comercial. Nenhum resultado automatizado preenche esta tabela.

1. Entrar e encontrar o caixa no Início.
2. Cadastrar produto simples sem categoria e sem grade; localizar o produto.
3. Preparar o caixa e registrar três vendas simples de um item com dinheiro/Pix.
   Cronometrar de abrir o checkout até a confirmação visível; registrar os três tempos.
4. Alternar as cinco abas; conferir preservação da busca e acessos por cargo.
5. Consultar Atividade, sair/entrar e confirmar o progresso da primeira venda.
6. Interromper a rede após login preparado, vender offline, reconectar e confirmar
   sincronização sem duplicar venda. Não apagar dados para simular falha.

| Operador | Aparelho/cargo | Tempos anteriores (s) | Tempos piloto (s) | Ajuda/erros | Avaliação |
| --- | --- | --- | --- | --- | --- |
| O1 | Pendente | — | — | — | Não realizada |
| O2 | Pendente | — | — | — | Não realizada |
| O3 | Pendente | — | — | — | Não realizada |
| O4 | Pendente | — | — | — | Não realizada |
| O5 | Pendente | — | — | — | Não realizada |

Aceitar quando os cinco concluírem a primeira venda, nenhuma venda duplicar ou
desaparecer, não houver acesso indevido por cargo e a mediana das 15 vendas simples
do piloto ficar abaixo de 15 segundos. Comparar tempos e erros com as 15 tentativas
anteriores; qualquer piora deve ser investigada antes de ampliar a distribuição.
Registrar dificuldades observadas como defeitos com reprodução, corrigir e repetir
o cenário afetado. A avaliação continua pendente até existirem essas observações.

## Acompanhamento no ambiente de testes

Após instalar o APK, renovar login para receber as flags. Conferir que aparecem
as cinco abas e que o checklist só aparece ao dono sem primeira venda concluída.

O comando local no backend atualizado é:

```sh
docker exec tatuzin-backend npm run experience:report -- --days 1 --app-version 1.0.1-pilot
```

Guardar o JSON por dia. Para uma empresa, acrescentar `--company-id ID`.
Ele mostra amostra, tentativas com falha e mediana declarada pelo app; menos de cinco
conclusões retorna `insufficient_data`. A mediana geral inclui checkouts complexos
e complementa a tabela, sem substituí-la. Comparar com `--app-version 1.0.0` quando
houver dados da versão anterior; ausência de dados não significa zero erros.

Durante cada sessão verificar `/api/readiness`, logs `http.request.failed` e o
relatório de jornada. Uma indisponibilidade, operação duplicada/perdida ou acesso
indevido exige interromper a ampliação e reverter a experiência.

## Liberação e reversão

O overlay `backend/docker-compose.experience-test.yml` liga onboarding e experiência
para todas as empresas **somente neste ambiente de testes**, conforme autorizado.
Não aplicar esse overlay a um lançamento comercial.

Reversão da experiência: recriar apenas o backend sem esse overlay e com os flags
gerais desligados; renovar login dos dispositivos. Não apagar o banco nem desfazer
as migrações aditivas. Se necessário, selecionar a imagem anterior registrada no
backup privado. O dump é recuperação de desastre; restaurá-lo pode perder operações
posteriores e não faz parte da reversão normal.

Publicação comercial e conclusão da avaliação humana permanecem condicionadas aos
resultados reais; a autorização atual cobre o ambiente de testes.
