# Seguranca do Admin Web

Este documento registra a politica de seguranca esperada para o `admin_web`.
Ele e um guia de produto/front-end e nao cria backend, endpoint, permissao real,
cookie, BFF, MFA ou mudanca de contrato de API nesta fase.

O `admin_web` e um painel interno da plataforma Tatuzin, separado do
`owner_web`, usado por suporte, operacao e auditoria administrativa. Toda
evolucao deve preservar o escopo interno, minimizar exposicao de dados sensiveis
e manter a rastreabilidade das acoes futuras.

## Escopo desta fase

- Documentar riscos e dependencias de hardening.
- Reforcar exibicao segura de dados sensiveis na UI.
- Manter a Central de Suporte e consoles operacionais em modo read-only.
- Registrar politicas para logs, dados sensiveis e acoes futuras.

Fora do escopo desta fase:

- Alterar autenticacao real.
- Alterar autorizacao real.
- Criar ou mudar backend, BFF, endpoints ou contratos de API.
- Criar migrations.
- Implementar Cookie HttpOnly, MFA, rate limit, CSP ou headers reais.
- Criar comandos operacionais reais ou acoes destrutivas.

## Limites do front-end

O front-end pode reduzir exposicao acidental, melhorar avisos e mascarar valores
na renderizacao. Ele nao substitui controles de seguranca server-side.

Controles obrigatorios futuros dependem do backend ou da infraestrutura:

- Cookie HttpOnly para tokens de sessao.
- BFF ou camada equivalente para evitar tokens long-lived no navegador.
- CSP e security headers.
- MFA para operadores administrativos.
- Expiracao de sessao e renovacao segura.
- Rate limit e protecao contra abuso.
- Autorizacao granular por papel, empresa, area e acao.
- Auditoria obrigatoria de toda acao sensivel.

## Riscos conhecidos

- Tokens no navegador continuam expostos a risco de XSS enquanto nao houver
  Cookie HttpOnly ou BFF.
- Dados retornados pela API podem conter campos sensiveis inesperados.
- Logs locais, logs de debug e payloads de erro podem vazar dados se nao forem
  sanitizados antes da exibicao.
- Acoes futuras de suporte podem causar impacto operacional se forem lancadas
  sem dry-run, motivo obrigatorio, confirmacao e trilha de auditoria.
- Permissoes visuais no front-end nao sao barreira de seguranca real.

## Politica de logs seguros

- Nao registrar Authorization, access token, refresh token, webhook secret,
  senha, hash, invite token, reset token ou payload completo de provider.
- Logs de debug devem registrar apenas presenca de credencial, como `present`
  ou `empty`, nunca o valor bruto.
- Erros exibidos na UI devem ser amigaveis e nao devem incluir headers,
  credenciais, stack traces sensiveis ou payloads completos.
- Payloads de auditoria ou billing devem passar por sanitizacao defensiva antes
  de renderizar.

## Politica de dados sensiveis na UI

- Exibir o minimo necessario para diagnostico de suporte.
- Mascarar identificadores longos quando o valor completo nao for necessario.
- Nunca exibir URLs completas de checkout, tokens, secrets, hashes ou headers.
- Usar fallbacks claros como `Nao informado`, `Indisponivel` e `Sem dados`.
- Manter avisos visuais de modo read-only em telas operacionais sensiveis.

## Politica para acoes futuras

Antes de qualquer comando real de suporte, a acao deve ter:

- Dry-run obrigatorio quando houver impacto operacional.
- Motivo obrigatorio informado pelo operador.
- Confirmacao explicita com resumo do impacto.
- Permissao granular validada no backend.
- Auditoria backend obrigatoria com empresa, operador, motivo, alvo e resultado.
- Estado de loading, sucesso e falha sem vazar payload sensivel.
- Protecao contra repeticao acidental.

Exemplos de acoes que nao devem existir sem esses controles: bloquear usuario,
revogar sessao, forcar sync, reenviar evento, corrigir conflito, alterar plano,
cancelar assinatura, resetar senha e expirar dispositivos.

## Checklist de hardening futuro

| Item | Dependencia | Status nesta fase |
| --- | --- | --- |
| Cookie HttpOnly | Backend/infra | Pendente |
| BFF para sessao admin | Backend/infra | Pendente |
| CSP | Infra/web server | Pendente |
| Security headers | Infra/web server | Pendente |
| MFA | Auth/backend | Pendente |
| Rate limit | Backend/infra | Pendente |
| Expiracao de sessao | Auth/backend | Pendente |
| Refresh seguro | Auth/backend | Pendente |
| Remocao de token long-lived do browser | Auth/backend/BFF | Pendente |
| Protecao de logs | Front-end/backend | Parcial |
| Auditoria obrigatoria | Backend | Pendente |
| Permissoes granulares | Backend | Pendente |
| Dry-run para acoes sensiveis | Backend/front-end | Pendente |
| Motivo obrigatorio | Backend/front-end | Pendente |
| Confirmacao explicita | Front-end/backend | Pendente |

## Recomendacoes para proximas fases

1. Definir modelo de permissao granular para suporte, auditoria, billing e sync.
2. Mover autenticacao administrativa para Cookie HttpOnly ou BFF.
3. Adicionar MFA para operadores administrativos.
4. Exigir auditoria backend para toda acao sensivel.
5. Adicionar CSP e security headers no servidor web do admin.
6. Revisar todos os payloads renderizados por telas de billing, sync e auditoria.
7. Criar testes de regressao para nao vazamento de tokens, secrets e headers.
