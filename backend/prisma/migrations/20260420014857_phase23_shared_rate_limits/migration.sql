-- CreateTable
CREATE TABLE "RateLimitBucket" (
    "bucketHash" TEXT NOT NULL,
    "scope" TEXT NOT NULL,
    "requestCount" INTEGER NOT NULL,
    "resetAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "RateLimitBucket_pkey" PRIMARY KEY ("bucketHash")
);

-- CreateIndex
CREATE INDEX "RateLimitBucket_scope_resetAt_idx" ON "RateLimitBucket"("scope", "resetAt");
