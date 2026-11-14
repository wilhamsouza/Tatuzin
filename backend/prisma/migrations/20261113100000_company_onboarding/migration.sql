ALTER TABLE "Company"
  ADD COLUMN "onboardingProductAt" TIMESTAMP(3),
  ADD COLUMN "onboardingCashAt" TIMESTAMP(3),
  ADD COLUMN "onboardingCompletedAt" TIMESTAMP(3);

-- Existing shops with real sales must not be forced through onboarding.
UPDATE "Company" AS company
SET "onboardingCompletedAt" = sales."firstSaleAt"
FROM (
  SELECT "companyId", MIN("soldAt") AS "firstSaleAt"
  FROM "Sale" WHERE status = 'active' GROUP BY "companyId"
) AS sales
WHERE company.id = sales."companyId";
