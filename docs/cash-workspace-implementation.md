# Caixa Tatuzin — execução local por etapas

Plano aprovado com os oito requisitos adicionais: conferência na abertura, fechamento cego opcional, cobertura dos efeitos financeiros, centavos inteiros, revisão gerencial de diferenças, caixas por funcionário independentes de aparelho, recuperação de encerramento inesperado e rollback compatível.

**Restrição de entrega:** nenhuma publicação em produção sem nova autorização do usuário. Os serviços publicados de Produtos/Estoque permanecem como estavam. Testes backend usam exclusivamente PostgreSQL descartável na porta 55442.

## Quadro de trabalho

| Frente | Responsável | Estado | Critério de revisão |
| --- | --- | --- | --- |
| App: abertura, conferência e fechamento acessível | cash_mobile | Em execução | Botão alcançável com teclado, rascunho durável, transação/outbox e recuperação testados |
| Políticas, sincronização e auditoria gerencial | cash_backend | Em execução | Compatibilidade legada, isolamento, congelamento do fechamento e concorrência testados |
| Painel gerencial | cash_owner | Em execução | Dados reais, revisão sem alterar valores originais, responsividade e permissões |
| Cobertura financeira e integração | root | Em execução | Pagamentos mistos, cancelamentos, devoluções, estornos, fiado parcial e centavos verificados |

As alterações anteriores do workspace serão preservadas. Cada frente possui área de escrita definida, com revisão sequencial pelo integrador.

## Regras iniciais

- Campo contado começa vazio; zero explícito é válido. Diferença exige justificativa.
- A calculadora de dinheiro alimenta abertura e fechamento; não afirma registro antes da persistência.
- Fechamento cego começa desligado por empresa. A política é capturada na abertura; configuração nova não altera sessões em andamento. Quando cego, esperado e diferença não aparecem ao operador antes de confirmar, e observação é exigida independentemente do resultado para não revelar a existência da diferença.
- Decisão final do usuário: caixa geral da empresa consolidado na nuvem, com um caixa individual por funcionário, independente do aparelho. A sessão central é compartilhada pelos aparelhos autorizados daquele funcionário; o fundo inicial não se repete ao trocar de dispositivo.
- Um aparelho novo precisa obter a sessão central e registrar participação online antes de operar nela offline. Sessões já recebidas funcionam offline. Aberturas concorrentes não podem somar dois fundos nem fundir operações silenciosamente.
- A conferência pode ser registrada offline. Ela fica pendente; não encerra o caixa central até todos os aparelhos participantes enviarem suas operações e confirmarem a mesma revisão. Novos movimentos invalidam a revisão/aceites anteriores. Mudança no saldo exige conferência e confirmação renovadas. Não presumir que aparelho sem eventos recentes já sincronizou.
- Sessões antigas permanecem identificadas como legadas; não são fundidas retroativamente, não têm seus fundos somados e seus fechamentos originais não são reescritos.
- Fechamento e evento são gravados na mesma transação local. O painel nunca altera o fechamento original ao revisar uma divergência.

## Retomada — caixa geral e funcionário

Frentes retomadas: backend (contratos V3/participantes/barreira de fechamento), app (identidade funcionário/cache/join e conferência pendente), painel (consolidado por funcionário/pendências) e integração (compatibilidade/cache/financeiro/testes/backup). Todos os dados de desenvolvimento permanecem locais; nenhuma autorização de produção foi dada.

Critério adicional: usuário do funcionário deve ser derivado da identidade autenticada no servidor, nunca de uma escolha livre do cliente. Outro funcionário não pode abrir, movimentar ou concluir o caixa individual alheio por trocar IDs. Gerência continua com consulta e revisão autorizadas. Eventos tardios, duplicados ou reordenados não podem duplicar fundo inicial ou permitir conclusão antes da barreira de sincronização.
