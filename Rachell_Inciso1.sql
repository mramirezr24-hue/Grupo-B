/* ===========================================================
   EQUIPO B — DML + LÓGICA DE NEGOCIO
   SPs de matrícula, triggers de control, MERGE desde staging,
   cargas y pruebas con TRY…CATCH.
   -----------------------------------------------------------
   NOTA: No se modifica nada del script original, solo se agrega.
   =========================================================== */

---------------------------------------------------------------
-- 1) Bitácoras y soporte de auditoría (idempotente)
---------------------------------------------------------------
IF OBJECT_ID('Seguridad.BitacoraMatriculas','U') IS NULL
BEGIN
  CREATE TABLE Seguridad.BitacoraMatriculas(
    BitacoraID BIGINT IDENTITY(1,1) CONSTRAINT PK_BitacoraMatriculas PRIMARY KEY,
    Accion NVARCHAR(20) NOT NULL, -- INSERT/DELETE
    AlumnoID INT NULL,
    CursoID INT NULL,
    Periodo CHAR(6) NULL,
    Usuario SYSNAME NOT NULL DEFAULT SUSER_SNAME(),
    Fecha DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    Detalle NVARCHAR(4000) NULL
  );
END
GO

IF OBJECT_ID('Seguridad.MergeLog_Cursos','U') IS NULL
BEGIN
  CREATE TABLE Seguridad.MergeLog_Cursos(
    MergeID BIGINT IDENTITY(1,1) CONSTRAINT PK_MergeLog_Cursos PRIMARY KEY,
    Accion NVARCHAR(10) NOT NULL, -- INSERT/UPDATE/DELETE
    CursoID INT NULL,
    CursoNombre NVARCHAR(100) NULL,
    Fecha DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
  );
END
GO