type JourneyReport = {
  source: string;
  timeBasis: string;
  since: string;
  steps: Array<{ name: string; events: number; companies: number; attempts: number; medianDurationMs: number | null }>;
};

export function summarizeExperience(report: JourneyReport) {
  const completed = report.steps.find((step) => step.name === 'checkout_completed');
  const started = report.steps.find((step) => step.name === 'checkout_started');
  const failed = report.steps.find((step) => step.name === 'checkout_failed');
  const sample = completed?.events ?? 0;
  const median = completed?.medianDurationMs ?? null;
  return {
    source: report.source,
    timeBasis: report.timeBasis,
    since: report.since,
    checkout: {
      startedAttempts: started?.attempts ?? 0,
      completedEvents: sample,
      failedAttempts: failed?.attempts ?? 0,
      medianDurationMs: median,
      targetDurationMs: 15000,
      status: sample < 5 || median == null ? 'insufficient_data'
        : median < 15000 ? 'within_target' : 'above_target',
    },
    humanValidation: 'requires_five_observed_operator_sessions',
    note: 'Telemetria declarada pelo cliente. A mediana agrega todos os checkouts; nao comprova a meta da venda simples nem substitui observacao humana. Etapas recebidas na janela nao sao uma coorte sequencial.',
    steps: report.steps,
  };
}
