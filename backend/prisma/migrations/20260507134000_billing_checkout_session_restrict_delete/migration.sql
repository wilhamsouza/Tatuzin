-- Preserve checkout session history from implicit company/user deletion.
ALTER TABLE "BillingCheckoutSession" DROP CONSTRAINT "BillingCheckoutSession_companyId_fkey";
ALTER TABLE "BillingCheckoutSession" ADD CONSTRAINT "BillingCheckoutSession_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "BillingCheckoutSession" DROP CONSTRAINT "BillingCheckoutSession_userId_fkey";
ALTER TABLE "BillingCheckoutSession" ADD CONSTRAINT "BillingCheckoutSession_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
