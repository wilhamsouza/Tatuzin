CREATE TABLE "ProductJourneyEvent" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "eventId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "attemptId" TEXT,
    "durationMs" INTEGER,
    "occurredAt" TIMESTAMP(3) NOT NULL,
    "receivedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "appVersion" TEXT NOT NULL,
    "plan" TEXT NOT NULL,
    "experienceProfile" TEXT NOT NULL,
    CONSTRAINT "ProductJourneyEvent_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "ProductJourneyEvent_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "ProductJourneyEvent_companyId_deviceId_eventId_key" ON "ProductJourneyEvent"("companyId", "deviceId", "eventId");
CREATE INDEX "ProductJourneyEvent_receivedAt_idx" ON "ProductJourneyEvent"("receivedAt");
CREATE INDEX "ProductJourneyEvent_companyId_name_receivedAt_idx" ON "ProductJourneyEvent"("companyId", "name", "receivedAt");
