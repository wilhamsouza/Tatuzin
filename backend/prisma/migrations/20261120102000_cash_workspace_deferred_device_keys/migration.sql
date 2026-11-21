-- Retain registered devices until their session/audit exists, while allowing tenant cascades atomically.
ALTER TABLE "CashWorkspaceParticipant" DROP CONSTRAINT "CashWorkspaceParticipant_deviceId_fkey";
ALTER TABLE "CashWorkspaceParticipant" ADD CONSTRAINT "CashWorkspaceParticipant_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "CompanyDevice"("id") ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE "CashClosureAck" DROP CONSTRAINT "CashClosureAck_deviceId_fkey";
ALTER TABLE "CashClosureAck" ADD CONSTRAINT "CashClosureAck_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "CompanyDevice"("id") ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED;
