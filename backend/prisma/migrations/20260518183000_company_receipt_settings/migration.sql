ALTER TABLE "Company"
ADD COLUMN "receiptDisplayName" TEXT,
ADD COLUMN "receiptDocument" TEXT,
ADD COLUMN "receiptPhone" TEXT,
ADD COLUMN "receiptAddress" TEXT,
ADD COLUMN "receiptFooterMessage" TEXT,
ADD COLUMN "showDocumentOnReceipt" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN "showPhoneOnReceipt" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN "showAddressOnReceipt" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN "showFooterMessageOnReceipt" BOOLEAN NOT NULL DEFAULT true;
