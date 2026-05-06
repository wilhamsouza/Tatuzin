-- Add operational local sequence guards for local-first PDV materializers.
ALTER TABLE "CashSession" ADD COLUMN "lastLocalSequence" INTEGER;
ALTER TABLE "OperationalOrder" ADD COLUMN "lastLocalSequence" INTEGER;
