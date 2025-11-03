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