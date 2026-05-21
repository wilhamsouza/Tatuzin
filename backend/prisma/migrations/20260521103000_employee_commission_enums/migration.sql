CREATE TYPE "EmployeeCommissionType" AS ENUM ('NONE', 'PERCENTAGE', 'FIXED_PER_SALE');
CREATE TYPE "EmployeeCommissionBase" AS ENUM ('GROSS_SALES', 'NET_SALES', 'GROSS_PROFIT');

UPDATE "EmployeeProfile"
SET
  "commissionType" = CASE
    WHEN "commissionType" IN ('NONE', 'PERCENTAGE', 'FIXED_PER_SALE') THEN "commissionType"
    ELSE 'NONE'
  END,
  "commissionBase" = CASE
    WHEN "commissionBase" IN ('GROSS_SALES', 'NET_SALES', 'GROSS_PROFIT') THEN "commissionBase"
    ELSE 'NET_SALES'
  END;

ALTER TABLE "EmployeeProfile"
  ALTER COLUMN "commissionType" TYPE "EmployeeCommissionType" USING "commissionType"::"EmployeeCommissionType",
  ALTER COLUMN "commissionBase" TYPE "EmployeeCommissionBase" USING "commissionBase"::"EmployeeCommissionBase",
  ALTER COLUMN "commissionType" SET NOT NULL,
  ALTER COLUMN "commissionBase" SET NOT NULL,
  ALTER COLUMN "commissionType" SET DEFAULT 'NONE',
  ALTER COLUMN "commissionBase" SET DEFAULT 'NET_SALES';
