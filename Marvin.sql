
---------------------------------------------------------------
-- 3) Triggers de control sobre Academico.Matriculas
---------------------------------------------------------------

-- T1: Validar que todo alumno insertado esté Activo (defensa adicional)
-- T2: Bitácora automática ante INSERT/DELETE fuera de los SPs

IF OBJECT_ID('Academico.trg_Matriculas_Control','TR') IS NOT NULL
  DROP TRIGGER Academico.trg_Matriculas_Control ON Academico.Matriculas;
GO
CREATE TRIGGER Academico.trg_Matriculas_Control
ON Academico.Matriculas
AFTER INSERT, DELETE
AS
BEGIN
  SET NOCOUNT ON;

  -- T1: si algún insert tiene alumno inactivo, revertir
  IF EXISTS (
    SELECT 1
    FROM inserte


	04_staging_merge.sql (Persona 4)
---------------------------------------------------------------
-- 4) Staging + MERGE de sincronización de cursos
---------------------------------------------------------------
-- Tabla de staging para cargas externas (lab)
IF OBJECT_ID('Lab.CursosStage','U') IS NULL
BEGIN
  CREATE TABLE Lab.CursosStage(
    CursoNombre       NVARCHAR(100) NOT NULL,
    CursoCreditosECTS TINYINT       NOT NULL
  );
END
GO


IF OBJECT_ID('Lab.usp_MergeCursosStage','P') IS NOT NULL
  DROP PROCEDURE Lab.usp_MergeCursosStage;
GO
CREATE PROCEDURE Lab.usp_MergeCursosStage
AS
BEGIN
  SET NOCOUNT ON;

  MERGE Academico.Cursos AS tgt
  USING (SELECT CursoNombre, CursoCreditosECTS FROM Lab.CursosStage) AS src
      ON tgt.CursoNombre = src.CursoNombre
  WHEN MATCHED AND tgt.CursoCreditosECTS <> src.CursoCreditosECTS
      THEN UPDATE SET tgt.CursoCreditosECTS = src.CursoCreditosECTS
  WHEN NOT MATCHED BY TARGET
      THEN INSERT (CursoNombre, CursoCreditosECTS)
           VALUES (src.CursoNombre, src.CursoCreditosECTS)
  WHEN NOT MATCHED BY SOURCE
      THEN DELETE
  OUTPUT $action AS Accion,
         inserted.CursoID,
         COALESCE(inserted.CursoNombre, deleted.CursoNombre) AS CursoNombre
  INTO Seguridad.MergeLog_Cursos(Accion, CursoID, CursoNombre);
END
GO
