# Controle de Versao Android

Este documento prepara o `admin_web` para controle futuro de versao do app
Android Tatuzin. Nesta fase, o painel apenas documenta a politica futura e
exibe sinais read-only baseados em versoes ja reportadas por dispositivos ou
sessoes. Nao ha alteracao no Android, backend, contratos reais, sync engine,
infraestrutura, FCM, push notification ou enforcement real.

## Objetivo

Permitir que suporte e operacao identifiquem, no futuro, empresas com apps
Android antigos, dispositivos sem versao reportada e possivel impacto antes de
uma politica de atualizacao obrigatoria.

## Conceitos

- Versao minima: abaixo dela, em fase futura, o app deve ser bloqueado ou exigir
  atualizacao antes de continuar.
- Versao recomendada: abaixo dela, em fase futura, o app pode exibir aviso, mas
  continuar funcionando.
- Versao instalada: versao reportada por dispositivo ou sessao.
- Atualizacao obrigatoria: regra futura que dependera de backend e Android para
  bloquear uso, mostrar mensagem e encaminhar para a Play Store.

Nesta fase, nenhuma dessas regras e aplicada de verdade.

## Limites atuais do Admin Web

O `admin_web` pode exibir `appVersion` quando a API ja retorna esse campo em
dispositivos ou sessoes. Ele nao sabe qual e a versao minima ou recomendada
oficial, nao calcula impacto real de bloqueio e nao envia comando ao Android.

Indicadores atuais sao apenas operacionais:

- OK: dispositivos Android reportaram versao.
- Atencao: ha dispositivos Android sem versao informada.
- Critico: reservado para fase futura com politica real ou risco confirmado.
- Sem dados: nao ha dispositivos Android ou dados suficientes.

## Riscos de versoes antigas

- Bugs de sync ja corrigidos em versoes novas.
- Falhas de compatibilidade com contratos futuros.
- Problemas de seguranca ou dependencia local.
- Dificuldade de suporte por falta de contexto de versao.
- Divergencia entre comportamento do app e regras atuais da plataforma.

## Relacao com telas do Admin Web

- Central de Suporte: deve mostrar resumo da versao Android da empresa.
- Dispositivos: deve mostrar versao instalada por dispositivo e fallback claro.
- Sync Center: ajuda a correlacionar versao do app com falhas, pendencias e
  conflitos, quando a versao estiver disponivel.
- Observabilidade: deve considerar empresas sem versao reportada como sinal de
  atencao, quando houver dispositivos Android.

## Dados futuros necessarios do backend

- Endpoint para politica global de versao Android.
- `minSupportedVersion`.
- `recommendedVersion`.
- `forceUpdate`.
- Versao instalada por dispositivo.
- Data da ultima versao reportada.
- Canal de distribuicao.
- Mensagem customizada de atualizacao.
- URL da Play Store.
- Auditoria para alteracao de politica.
- Permissoes para alterar politica.
- Dry-run antes de politica obrigatoria.

## Comportamento esperado no Android em fase futura

- Consultar politica de versao de forma segura.
- Comparar versao instalada com minima e recomendada.
- Mostrar aviso quando estiver abaixo da versao recomendada.
- Bloquear ou exigir atualizacao quando estiver abaixo da versao minima.
- Exibir mensagem clara e link para a Play Store.
- Continuar sem travar quando a politica estiver indisponivel, conforme regra
  definida pelo backend.

## Seguranca e auditoria futuras

Quando a alteracao real de politica existir, deve exigir:

- Permissao especifica.
- Motivo obrigatorio.
- Confirmacao explicita.
- Dry-run mostrando impacto.
- Quantidade de dispositivos afetados.
- Auditoria backend.
- Ator/admin identificado.
- Rollback ou plano de reversao, se aplicavel.

## Fora do escopo desta fase

- Enforcement real de versao minima.
- Atualizacao obrigatoria real.
- Bloqueio de app antigo.
- Push notification ou FCM.
- Endpoint novo.
- Mudanca de contrato real de API.
- Alteracao em Android, backend, sync engine ou infraestrutura.
