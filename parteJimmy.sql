02_sps_matricula.sql (Persona 2)
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
