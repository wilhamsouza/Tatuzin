# Checklist manual - pedidos para loja de roupas

Use este roteiro em aparelho fisico antes de liberar o fluxo de pedidos em producao. Registre o aparelho, versao do app, usuario, empresa/tenant e data do teste.

## Preparacao

- [ ] Abrir o app em uma empresa de teste com produtos simples e produtos com grade.
- [ ] Confirmar que existe pelo menos uma variante com SKU, cor e tamanho cadastrados.
- [ ] Confirmar o estoque fisico inicial do produto simples.
- [ ] Confirmar o estoque fisico inicial da variante que sera testada.
- [ ] Confirmar que nao ha reservas antigas ativas para os produtos do teste.

## Criacao e rascunho

- [ ] Criar um novo pedido de venda.
- [ ] Confirmar que o pedido nasce como `Rascunho`.
- [ ] Confirmar que o rascunho ainda nao cria reserva de estoque.
- [ ] Preencher cliente/identificador, telefone e observacao geral.
- [ ] Sair e voltar para o detalhe do pedido, confirmando que os dados foram preservados.

## Itens e grade

- [ ] Adicionar um produto simples.
- [ ] Confirmar nome, quantidade, preco e subtotal no card do item.
- [ ] Adicionar um produto com variacao.
- [ ] Confirmar exibicao de SKU, cor e tamanho no card do item.
- [ ] Confirmar que duas variantes do mesmo produto aparecem como opcoes distintas.
- [ ] Selecionar uma variante e confirmar que outra variante do mesmo produto nao fica marcada.
- [ ] Confirmar que a busca mostra disponibilidade real da opcao.

## Disponibilidade real

- [ ] Verificar exibicao de estoque disponivel e reservado no adicionador/editor de itens.
- [ ] Tentar adicionar quantidade maior que o disponivel real.
- [ ] Confirmar que a acao e bloqueada com mensagem clara de estoque insuficiente.
- [ ] Confirmar que produtos/variantes sem disponibilidade nao podem ser adicionados.
- [ ] Confirmar que reservas `released` e `converted` nao reduzem o disponivel.

## Envio para separacao

- [ ] Enviar o pedido para separacao.
- [ ] Confirmar mensagem de sucesso.
- [ ] Confirmar status `Aguardando separacao`.
- [ ] Confirmar que os itens nao podem mais ser editados, adicionados ou removidos.
- [ ] Confirmar no banco/suporte tecnico que a reserva foi criada como `active`.
- [ ] Confirmar que o estoque fisico nao foi baixado ao reservar.

## Cancelamento

- [ ] Cancelar um pedido ainda em rascunho.
- [ ] Confirmar que nenhuma reserva foi criada.
- [ ] Criar outro pedido, enviar para separacao e cancelar.
- [ ] Confirmar que a reserva `active` virou `released`.
- [ ] Confirmar que o estoque fisico nao mudou ao cancelar.
- [ ] Confirmar que a disponibilidade real voltou a aumentar.

## Concorrencia de variante

- [ ] Criar uma variante com estoque 1.
- [ ] Criar pedido A com essa variante e enviar para separacao.
- [ ] Criar pedido B tentando usar a mesma variante.
- [ ] Confirmar que pedido B nao consegue reservar/finalizar a separacao por falta de disponibilidade.
- [ ] Cancelar pedido A.
- [ ] Confirmar que pedido B passa a enxergar disponibilidade novamente.

## Separacao e entrega

- [ ] Marcar pedido como `Em separacao`.
- [ ] Confirmar que a reserva continua `active`.
- [ ] Marcar pedido como `Pronto para retirada`.
- [ ] Confirmar que a reserva continua `active`.
- [ ] Marcar pedido como `Entregue`.
- [ ] Confirmar que pedido entregue sem faturamento ainda nao converte reserva.

## Faturamento

- [ ] Faturar pedido entregue com produto simples.
- [ ] Confirmar que a venda foi criada.
- [ ] Confirmar que a reserva virou `converted`.
- [ ] Confirmar que o estoque fisico baixou uma unica vez.
- [ ] Faturar pedido entregue com variante.
- [ ] Confirmar que a baixa ocorreu na variante correta.
- [ ] Confirmar que SKU, cor e tamanho foram preservados no item da venda.
- [ ] Tentar faturar pedido cancelado.
- [ ] Confirmar bloqueio com mensagem clara.
- [ ] Tentar faturar pedido ja faturado.
- [ ] Confirmar bloqueio e ausencia de nova baixa de estoque.

## Romaneio e comprovantes

- [ ] Visualizar romaneio de separacao.
- [ ] Confirmar que exibe produto, quantidade, SKU, cor e tamanho.
- [ ] Confirmar que observacao do item aparece quando preenchida.
- [ ] Confirmar que observacao geral aparece quando preenchida.
- [ ] Imprimir romaneio em impressora configurada.
- [ ] Confirmar que linhas longas quebram sem cortar informacao importante.
- [ ] Visualizar comprovante de venda.
- [ ] Confirmar que os textos usam linguagem de loja de roupas/pedidos.

## Textos e visual

- [ ] Confirmar que telas de pedidos nao exibem `cozinha`.
- [ ] Confirmar que telas de pedidos nao exibem `comanda`.
- [ ] Confirmar que telas de pedidos nao exibem `ticket operacional`.
- [ ] Confirmar que status usam `separacao`, `pronto para retirada` e `entregue`.
- [ ] Testar em celular pequeno.
- [ ] Confirmar que botoes nao estouram largura.
- [ ] Confirmar que SKU/cor/tamanho nao sobrepoem preco, quantidade ou acoes.
- [ ] Testar em modo escuro, se habilitado no aparelho/app.
- [ ] Confirmar contraste e leitura dos cards no modo escuro.

## Encerramento

- [ ] Anotar todos os bugs encontrados com tela, pedido, produto, variante e passos.
- [ ] Repetir os cenarios criticos apos qualquer correcao.
- [ ] Guardar evidencias de estoque antes/depois para reserva, cancelamento e faturamento.
