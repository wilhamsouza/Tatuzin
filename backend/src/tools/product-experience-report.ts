import { prisma } from '../database/prisma';
import { journeyReportQuerySchema } from '../modules/product-journey/product-journey.schemas';
import { ProductJourneyService } from '../modules/product-journey/product-journey.service';
import { summarizeExperience } from '../modules/product-journey/experience-summary';

async function main() {
  const input: Record<string, string> = {};
  const flags: Record<string, string> = { '--days': 'days', '--company-id': 'companyId', '--app-version': 'appVersion' };
  const args = process.argv.slice(2);
  for (let index = 0; index < args.length; index += 2) {
    const key = flags[args[index]];
    if (!key || !args[index + 1] || args[index + 1].startsWith('--')) {
      throw new Error('Uso: experience:report [--days 1..90] [--company-id ID] [--app-version VERSION]');
    }
    input[key] = args[index + 1];
  }
  const query = journeyReportQuerySchema.parse({ days: 1, ...input });
  const report = await new ProductJourneyService().report(query);
  console.log(JSON.stringify(summarizeExperience(report), null, 2));
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : 'Falha ao ler o relatorio.');
  process.exitCode = 1;
}).finally(() => prisma.$disconnect());
