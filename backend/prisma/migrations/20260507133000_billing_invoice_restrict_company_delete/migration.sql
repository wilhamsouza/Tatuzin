-- Keep invoice history from being removed automatically with company deletion.
ALTER TABLE "BillingInvoice" DROP CONSTRAINT "BillingInvoice_companyId_fkey";
ALTER TABLE "BillingInvoice" ADD CONSTRAINT "BillingInvoice_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
