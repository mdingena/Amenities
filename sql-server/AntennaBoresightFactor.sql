SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:      Marc Dingena
-- Version:     1.0.0
-- Description: Returns boresight of two antennas, expressed as a factor.
--              Boresight == +1  -> Antennas are both directly facing each other.
--              Boresight == -1  -> Antennas are both facing away from each other.
--              Boresight ==  0  -> Antennas are both facing same direction (azimuth).
--              Boresight >   0  -> Boresights will intersect somewhere.
--              Boresight <   0  -> Boresights will never intersect.
-- =============================================
CREATE FUNCTION [dbo].[AntennaBoresightFactor]
(
	@P1X bigint,       -- Position 1 X
	@P1Y bigint,       -- Position 1 Y
	@P2X bigint,       -- Position 2 X
	@P2Y bigint,       -- Position 2 Y
	@P1A bigint,       -- Position 1 Azimuth
	@P2A bigint = NULL -- Position 2 Azimuth (optional, default = arctangent to Position 1)
)
RETURNS float
AS
BEGIN
	DECLARE
		@PdX bigint, -- Delta of X Position
		@PdY bigint, -- Delta of Y Position
		@PdZ float,  -- Distance between Positions 1 and 2
		@AT1 bigint, -- ArcTangent of Position 1
		@AT2 bigint, -- ArcTangent of Position 2 (equals AT1 + 180°)
		@Ad1 float,  -- Delta of angles P1A and AT1 (absolute)
		@Ad2 float,  -- Delta of angles P2A and AT2 (absolute)
		@BS1 float,  -- Boresight factor for Position 1
		@BS2 float   -- Boresight factor for Position 2
	;
	SET @PdX = @P1X - @P2X;
	SET @PdY = @P1Y - @P2Y;
	SET @PdZ = SQRT( POWER( ABS( @PdX ), 2 ) + POWER( ABS( @PdY ), 2 ) );
	SET @AT1 = CASE
		WHEN @PdZ = 0 THEN 0
		ELSE CONVERT( int, 180 + ATN2( @PdX, @PdY ) * 180 / PI() ) % 360
	END;
	SET @AT2 = ( @AT1 + 180 ) % 360;
	SET @P2A = CASE
		WHEN @P2A IS NOT NULL THEN @P2A
		ELSE @AT2
	END;
	SET @Ad1 = ABS( ABS( @AT1 - @P1A ) - ( ABS( @AT1 - @P1A ) % 180 ) * 2 );
	SET @Ad2 = ABS( ABS( @AT2 - @P2A ) - ( ABS( @AT2 - @P2A ) % 180 ) * 2 );
	SET @BS1 = CASE
		WHEN @PdZ = 0 THEN 1
		ELSE 1 - @Ad1 / 180
	END;
	SET @BS2 = CASE
		WHEN @PdZ = 0 THEN 1
		ELSE 1 - @Ad2 / 180
	END;
	RETURN 2 * ( ( @BS1 + @BS2 ) / 2 ) - 1;
END

