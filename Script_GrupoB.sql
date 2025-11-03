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
    BitacoraID     BIGINT IDENTITY(1,1) CONSTRAINT PK_BitacoraMatriculas PRIMARY KEY,
    Accion         NVARCHAR(20)   NOT NULL,   -- INSERT/DELETE
    AlumnoID       INT            NULL,
    CursoID        INT            NULL,
    Periodo        CHAR(6)        NULL,
    Usuario        SYSNAME        NOT NULL DEFAULT SUSER_SNAME(),
    Fecha          DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    Detalle        NVARCHAR(4000) NULL
  );
END
GO

IF OBJECT_ID('Seguridad.MergeLog_Cursos','U') IS NULL
BEGIN
  CREATE TABLE Seguridad.MergeLog_Cursos(
    MergeID      BIGINT IDENTITY(1,1) CONSTRAINT PK_MergeLog_Cursos PRIMARY KEY,
    Accion       NVARCHAR(10) NOT NULL,      -- INSERT/UPDATE/DELETE
    CursoID      INT          NULL,
    CursoNombre  NVARCHAR(100) NULL,
    Fecha        DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
  );
END
GO

---------------------------------------------------------------
-- 2) SPs de negocio: Matricular y Desmatricular
---------------------------------------------------------------
-- Reglas implementadas:
--  R1: Alumno debe existir y estar Activo = 1
--  R2: Curso debe existir
--  R3: No duplicar (AlumnoID, CursoID, Periodo)
--  R4: Todo dentro de transacción con TRY…CATCH

IF OBJECT_ID('Academico.usp_MatricularAlumno','P') IS NOT NULL
  DROP PROCEDURE Academico.usp_MatricularAlumno;
GO
CREATE PROCEDURE Academico.usp_MatricularAlumno
  @AlumnoID INT,
  @CursoID  INT,
  @Periodo  CHAR(6)
AS
BEGIN
  SET NOCOUNT ON;
  BEGIN TRY
    BEGIN TRAN;

    -- R1: validar alumno activo
    IF NOT EXISTS (
      SELECT 1 FROM Academico.Alumnos
      WHERE AlumnoID = @AlumnoID AND AlumnoActivo = 1
    )
      THROW 50001, 'Alumno inexistente o inactivo.', 1;

    -- R2: validar curso
    IF NOT EXISTS (SELECT 1 FROM Academico.Cursos WHERE CursoID = @CursoID)
      THROW 50002, 'Curso inexistente.', 1;

    -- R3: evitar duplicados
    IF EXISTS (
      SELECT 1 FROM Academico.Matriculas
      WHERE AlumnoID = @AlumnoID AND CursoID = @CursoID AND MatriculaPeriodo = @Periodo
    )
      THROW 50003, 'Ya existe la matrícula para ese periodo.', 1;

    INSERT INTO Academico.Matriculas(AlumnoID, CursoID, MatriculaPeriodo)
    VALUES (@AlumnoID, @CursoID, @Periodo);

    -- Bitácora
    INSERT INTO Seguridad.BitacoraMatriculas(Accion, AlumnoID, CursoID, Periodo, Detalle)
    VALUES (N'INSERT', @AlumnoID, @CursoID, @Periodo, N'usp_MatricularAlumno');

    COMMIT TRAN;

    -- Resultado “amigable” para pruebas
    SELECT Exito = 1, Mensaje = N'Matrícula creada';
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRAN;
    DECLARE @msg nvarchar(4000) = ERROR_MESSAGE();
    SELECT Exito = 0, Mensaje = @msg;
    RETURN;
  END CATCH
END
GO
-- Por qué: encapsula reglas de negocio, valida antes de insertar y deja evidencia.

IF OBJECT_ID('Academico.usp_DesmatricularAlumno','P') IS NOT NULL
  DROP PROCEDURE Academico.usp_DesmatricularAlumno;
GO
CREATE PROCEDURE Academico.usp_DesmatricularAlumno
  @AlumnoID INT,
  @CursoID  INT,
  @Periodo  CHAR(6)
AS
BEGIN
  SET NOCOUNT ON;
  BEGIN TRY
    BEGIN TRAN;

    IF NOT EXISTS (
      SELECT 1 FROM Academico.Matriculas
      WHERE AlumnoID = @AlumnoID AND CursoID = @CursoID AND MatriculaPeriodo = @Periodo
    )
      THROW 50004, 'No hay matrícula para eliminar.', 1;

    DELETE FROM Academico.Matriculas
    WHERE AlumnoID = @AlumnoID AND CursoID = @CursoID AND MatriculaPeriodo = @Periodo;

    INSERT INTO Seguridad.BitacoraMatriculas(Accion, AlumnoID, CursoID, Periodo, Detalle)
    VALUES (N'DELETE', @AlumnoID, @CursoID, @Periodo, N'usp_DesmatricularAlumno');

    COMMIT TRAN;
    SELECT Exito = 1, Mensaje = N'Matrícula eliminada';
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRAN;
    DECLARE @msg nvarchar(4000) = ERROR_MESSAGE();
    SELECT Exito = 0, Mensaje = @msg;
    RETURN;
  END CATCH
END
GO
-- Por qué: proceso inverso controlado y auditable.

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
    FROM inserted i
    JOIN Academico.Alumnos a ON a.AlumnoID = i.AlumnoID
    WHERE a.AlumnoActivo = 0
  )
  BEGIN
    ROLLBACK TRANSACTION;
    THROW 50005, 'No se permite matricular alumnos inactivos (trigger).', 1;
  END

  -- T2: bitácora (INSERT/DELETE directos)
  IF EXISTS (SELECT 1 FROM inserted)
    INSERT INTO Seguridad.BitacoraMatriculas(Accion, AlumnoID, CursoID, Periodo, Detalle)
    SELECT N'INSERT', i.AlumnoID, i.CursoID, i.MatriculaPeriodo, N'trigger'
    FROM inserted i;

  IF EXISTS (SELECT 1 FROM deleted)
    INSERT INTO Seguridad.BitacoraMatriculas(Accion, AlumnoID, CursoID, Periodo, Detalle)
    SELECT N'DELETE', d.AlumnoID, d.CursoID, d.MatriculaPeriodo, N'trigger'
    FROM deleted d;
END
GO
-- Por qué: defensa en profundidad; registra operaciones aun si no usan los SPs.

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

-- MERGE para upsert desde staging hacia catálogo de cursos.
-- Se usa CursoNombre como clave natural, coherente con UQ_Cursos_Nombre.
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
-- Por qué: MERGE sincroniza altas, cambios y bajas; OUTPUT deja evidencia.

---------------------------------------------------------------
-- 5) Carga de ejemplo y ejecución de MERGE (opcional para demo)
---------------------------------------------------------------
-- Limpio y cargo staging de muestra
TRUNCATE TABLE Lab.CursosStage;
INSERT INTO Lab.CursosStage(CursoNombre, CursoCreditosECTS)
VALUES (N'Bases de Datos', 6),
       (N'Análisis de Datos', 5),
       (N'Algoritmos', 6);

-- Ejecutar sincronización
EXEC Lab.usp_MergeCursosStage;
-- SELECT * FROM Seguridad.MergeLog_Cursos; -- evidencias

---------------------------------------------------------------
-- 6) Pack de pruebas automatizado (TRY…CATCH + bitácora)
---------------------------------------------------------------
IF OBJECT_ID('Lab.Pruebas','U') IS NULL
BEGIN
  CREATE TABLE Lab.Pruebas(
    PruebaID  INT IDENTITY(1,1) CONSTRAINT PK_Pruebas PRIMARY KEY,
    Nombre    NVARCHAR(200) NOT NULL,
    OK        BIT           NOT NULL,
    Detalle   NVARCHAR(4000) NULL,
    Fecha     DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
  );
END
GO

IF OBJECT_ID('Lab.usp_RunPruebas_B','P') IS NOT NULL
  DROP PROCEDURE Lab.usp_RunPruebas_B;
GO
CREATE PROCEDURE Lab.usp_RunPruebas_B
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @alumno INT, @curso INT, @periodo CHAR(6) = '2024S2';

  -- Datos mínimos para probar (idempotente: crea si no existen)
  IF NOT EXISTS (SELECT 1 FROM Academico.Alumnos WHERE AlumnoNombre = N'Ana' AND AlumnoApellido = N'Prueba')
    INSERT INTO Academico.Alumnos(AlumnoNombre, AlumnoApellido, AlumnoEmail, AlumnoEdad, AlumnoActivo)
    VALUES (N'Ana', N'Prueba', N'ana.prueba@example.com', 20, 1);

  SELECT @alumno = AlumnoID FROM Academico.Alumnos
  WHERE AlumnoNombre = N'Ana' AND AlumnoApellido = N'Prueba';

  IF NOT EXISTS (SELECT 1 FROM Academico.Cursos WHERE CursoNombre = N'Bases de Datos')
    INSERT INTO Academico.Cursos(CursoNombre, CursoCreditosECTS) VALUES (N'Bases de Datos', 6);

  SELECT @curso = CursoID FROM Academico.Cursos WHERE CursoNombre = N'Bases de Datos';

  BEGIN TRY
    -- P1: matrícula ok
    EXEC Academico.usp_MatricularAlumno @alumno, @curso, @periodo;

    INSERT INTO Lab.Pruebas(Nombre, OK, Detalle)
    VALUES (N'P1: Matricular alumno activo', 1, N'Insert exitoso');

  END TRY
  BEGIN CATCH
    INSERT INTO Lab.Pruebas(Nombre, OK, Detalle)
    VALUES (N'P1: Matricular alumno activo', 0, ERROR_MESSAGE());
  END CATCH

  BEGIN TRY
    -- P2: duplicado debe fallar
    EXEC Academico.usp_MatricularAlumno @alumno, @curso, @periodo;
    INSERT INTO Lab.Pruebas(Nombre, OK, Detalle)
    VALUES (N'P2: Duplicado detectado', 0, N'No falló como se esperaba');
  END TRY
  BEGIN CATCH
    INSERT INTO Lab.Pruebas(Nombre, OK, Detalle)
    VALUES (N'P2: Duplicado detectado', 1, ERROR_MESSAGE());
  END CATCH

  BEGIN TRY
    -- P3: desmatricular ok
    EXEC Academico.usp_DesmatricularAlumno @alumno, @curso, @periodo;
    INSERT INTO Lab.Pruebas(Nombre, OK, Detalle)
    VALUES (N'P3: Desmatricular', 1, N'Delete exitoso');
  END TRY
  BEGIN CATCH
    INSERT INTO Lab.Pruebas(Nombre, OK, Detalle)
    VALUES (N'P3: Desmatricular', 0, ERROR_MESSAGE());
  END CATCH

  -- Resultado
  SELECT * FROM Lab.Pruebas ORDER BY PruebaID DESC;
END
GO
-- Por qué: automatiza verificación funcional; cada prueba captura éxito/error.

-- Ejecución sugerida del pack:
-- EXEC Lab.usp_RunPruebas_B;