-- ============================================================================
-- Lab 03 - Vector Search on Azure SQL DB
-- ----------------------------------------------------------------------------
-- This script:
--   1. Creates the workshop participants (Entra group) as a contained user,
--      with read/write permissions on the lab schema.
--   2. Creates the demo `documents` table with a VECTOR(1536) column for
--      text-embedding-3-small embeddings.
--   3. Adds a cosine-similarity helper inline-table-valued function so the
--      lab notebook can call `SELECT * FROM dbo.search_documents(@q, 5)`.
--
-- Run as the Entra SQL admin (the principal set in main-day2.bicep).
--
-- Variables substituted by grant-user-access-day2.ps1:
--     $(WORKSHOP_GROUP_NAME)  - Entra group display name for participants
-- ============================================================================

-- 1. Workshop group as a contained Entra user
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$(WORKSHOP_GROUP_NAME)')
BEGIN
    DECLARE @sql nvarchar(max) = N'CREATE USER [$(WORKSHOP_GROUP_NAME)] FROM EXTERNAL PROVIDER;';
    EXEC sp_executesql @sql;
END
GO

ALTER ROLE db_datareader ADD MEMBER [$(WORKSHOP_GROUP_NAME)];
ALTER ROLE db_datawriter ADD MEMBER [$(WORKSHOP_GROUP_NAME)];
GO

-- 2. Demo table with native VECTOR data type
IF OBJECT_ID(N'dbo.documents', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.documents
    (
        id          int           IDENTITY(1,1) PRIMARY KEY,
        title       nvarchar(200) NOT NULL,
        body        nvarchar(max) NOT NULL,
        embedding   VECTOR(1536)  NULL,
        created_at  datetime2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
    );
END
GO

-- 3. Cosine similarity search function
-- VECTOR_DISTANCE returns cosine *distance* (1 - cosine similarity), so smaller = more similar.
IF OBJECT_ID(N'dbo.search_documents', N'IF') IS NOT NULL
    DROP FUNCTION dbo.search_documents;
GO

CREATE FUNCTION dbo.search_documents
(
    @query VECTOR(1536),
    @top   int
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (@top)
        d.id,
        d.title,
        d.body,
        1 - VECTOR_DISTANCE('cosine', d.embedding, @query) AS cosine_similarity
    FROM dbo.documents d
    WHERE d.embedding IS NOT NULL
    ORDER BY VECTOR_DISTANCE('cosine', d.embedding, @query) ASC
);
GO

GRANT SELECT ON dbo.documents TO [$(WORKSHOP_GROUP_NAME)];
GRANT INSERT, UPDATE, DELETE ON dbo.documents TO [$(WORKSHOP_GROUP_NAME)];
GRANT SELECT ON dbo.search_documents TO [$(WORKSHOP_GROUP_NAME)];
GO

PRINT 'Lab 03 vector search setup complete.';
PRINT '  Table:    dbo.documents (VECTOR(1536))';
PRINT '  Function: dbo.search_documents(@query, @top)';
PRINT '  User:     $(WORKSHOP_GROUP_NAME)';
GO
