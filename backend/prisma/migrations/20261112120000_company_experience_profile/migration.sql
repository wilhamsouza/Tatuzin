ALTER TABLE "Company" ADD COLUMN "experienceProfile" TEXT NOT NULL DEFAULT 'moda';

-- Infer only once. Subsequent catalogue changes must not overwrite the owner's choice.
UPDATE "Company" AS company
SET "experienceProfile" = CASE
  WHEN EXISTS (SELECT 1 FROM "Product" p WHERE p."companyId" = company.id AND p.niche = 'moda')
    AND NOT EXISTS (SELECT 1 FROM "Product" p WHERE p."companyId" = company.id AND p.niche <> 'moda') THEN 'moda'
  WHEN EXISTS (SELECT 1 FROM "Product" p WHERE p."companyId" = company.id AND p.niche = 'alimentacao')
    AND NOT EXISTS (SELECT 1 FROM "Product" p WHERE p."companyId" = company.id AND p.niche <> 'alimentacao') THEN 'alimentacao'
  ELSE 'misto'
END;

ALTER TABLE "Company" ADD CONSTRAINT "Company_experienceProfile_check"
  CHECK ("experienceProfile" IN ('moda', 'alimentacao', 'misto'));
