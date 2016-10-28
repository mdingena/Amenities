SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:      Marc Dingena
-- Version:     1.1.0
-- Description: Returns boresight of two antennas, expressed as a factor.
--              Boresight == +1  -> Antennas are both directly facing each other.
--              Boresight == -1  -> Antennas are both facing away from each other.
--              Boresight ==  0  -> Antennas are both facing same direction (azimuth).
--              Boresight >   0  -> Boresights will intersect somewhere.
--              Boresight <   0  -> Boresights will never intersect.
-- =============================================
CREATE FUNCTION [dbo].[AntennaBoresightFactor]
(
	@X1 int,        -- Position 1 X
	@Y1 int,        -- Position 1 Y
	@X2 int,        -- Position 2 X
	@Y2 int,        -- Position 2 Y
	@A1 int,        -- Position 1 Azimuth
	@A2 int = NULL, -- Position 2 Azimuth (optional, default = arctangent to Position 1)
	@E bit  = 1     -- Enable distance entropy (optional, default = enabled)
)
RETURNS float
AS
BEGIN
	DECLARE -- Constants
		@BeamWidth int,
		@BreakEvenDistance bigint,
		@DistanceFactor float,
		@MaxEntropyAllowed float,
		@Q1 int,
		@Q2 int,
		@Q3 int,
		@Q4 int
	;
	SET @BeamWidth = 60;
	SET @BreakEvenDistance = 5000; -- Break even at 5 km == 99% entropy reached at ~21.5 km
	SET @DistanceFactor = 1.05;
	SET @MaxEntropyAllowed = 0.1;
	SET @Q1 = 1;
	SET @Q2 = 2;
	SET @Q3 = 4;
	SET @Q4 = 8;
	DECLARE -- Variables
		@dX bigint, -- Delta of X Position
		@dY bigint, -- Delta of Y Position
		@dZ float,  -- Distance between Positions 1 and 2
		@fZ float,  -- Use distance factor to decrease severity of high boresight
		@T1 int,    -- ArcTangent of Position 1
		@T2 int,    -- ArcTangent of Position 2 (equals P1AT + 180°)
		@dA1 float, -- Delta of angles P1A and P1T (absolute)
		@dA2 float, -- Delta of angles P2A and P2T (absolute)
		@D1 int,    -- @dA1 == 0 -> 1
		@D2 int,    -- @dA2 == 0 -> 1
		@dT1 int,   -- Delta of ArcTangent of Azimuth 1
		@dT2 int,   -- Delta of ArcTangent of Azimuth 2
		@B1 float,  -- Boresight factor for Position 1
		@B2 float,  -- Boresight factor for Position 2
		@F1 float,  -- Adjusted Boresight for Position 1
		@F2 float,  -- Adjusted Boresight for Position 2
		@Q int,     -- Quadrant mapping
		@P float,   -- Power of LOG( @B# ),
		@B float    -- Resulting Boresight
	;
	SET @dX = @X1 - @X2;
	SET @dY = @Y1 - @Y2;
	SET @dZ = SQRT( POWER( ABS( @dX ), 2 ) + POWER( ABS( @dY ), 2 ) );
	SET @fZ = CASE
		WHEN @E = 0 THEN 1
		ELSE 1 - (((( @BreakEvenDistance + POWER( @dZ, 3) ) / @BreakEvenDistance ) - ( ( POWER( @BreakEvenDistance, 3 ) ) / @BreakEvenDistance ) ) / POWER( 1000, 3 ) ) / 2
	END;
	SET @fZ = CASE
		WHEN @fZ > 1 THEN 1
		WHEN @fZ < @MaxEntropyAllowed THEN @MaxEntropyAllowed
		ELSE @fZ
	END;
	SET @T1 = CASE
		WHEN @dZ = 0 THEN 0
		ELSE CONVERT( bigint, 180 + ATN2( @dX, @dY ) * 180 / PI() ) % 360
	END;
	SET @T2 = ( @T1 + 180 ) % 360;
	SET @A2 = CASE
		WHEN @A2 IS NOT NULL THEN @A2
		ELSE @T2
	END;
	SET @dA1 = ABS( ABS( @T1 - @A1 ) - ( ABS( @T1 - @A1 ) % 180 ) * 2 );
	SET @dA2 = ABS( ABS( @T2 - @A2 ) - ( ABS( @T2 - @A2 ) % 180 ) * 2 );
	SET @D1 = CASE
		WHEN @dA1 = 0 THEN 1
		ELSE @dA1
	END;
	SET @D2 = CASE
		WHEN @dA2 = 0 THEN 1
		ELSE @dA2
	END;
	SET @dT1 = ( @A1 - @T1 + 360 ) % 360;
	SET @dT2 = ( @A2 - @T2 + 360 ) % 360;
	SET @Q = CASE
		WHEN @dT1 BETWEEN 0 AND 89 THEN @Q1
		WHEN @dT1 BETWEEN 90 AND 180 THEN @Q2
		WHEN @dT1 BETWEEN 180 AND 270 THEN @Q3
		WHEN @dT1 BETWEEN 271 AND 360 THEN @Q4
	END + CASE
		WHEN @dT2 BETWEEN 0 AND 89 THEN @Q1
		WHEN @dT2 BETWEEN 90 AND 180 THEN @Q2
		WHEN @dT2 BETWEEN 180 AND 270 THEN @Q3
		WHEN @dT2 BETWEEN 271 AND 360 THEN @Q4
	END;
	SET @P = CASE
		WHEN @Q = ( @Q1 + @Q4 ) THEN 32                       -- 9
		WHEN @Q = ( @Q1 + @Q1 ) OR @Q = ( @Q4 + @Q4 ) THEN 16 -- 2 OR 16
		WHEN @Q = ( @Q1 + @Q3 ) OR @Q = ( @Q4 + @Q2 ) THEN 8  -- 5 OR 10
		WHEN @Q = ( @Q1 + @Q2 ) OR @Q = ( @Q4 + @Q3 ) THEN 4  -- 3 OR 12
		WHEN @Q = ( @Q2 + @Q3 ) THEN 2                        -- 6
		WHEN @Q = ( @Q2 + @Q2) OR @Q = ( @Q3 + @Q3 ) THEN 1   -- 4 OR 8
	END;
	SET @B1 = CASE
		WHEN @dZ = 0 THEN 1
		ELSE 1 - @dA1 / 180
	END;
	SET @B2 = CASE
		WHEN @dZ = 0 THEN 1
		ELSE 1 - @dA2 / 180
	END;
	SET @F1 = @B1 * ( 1 - POWER( LOG( @D1 ) / LOG( 360 ), @P * POWER( @BreakEvenDistance / @dZ, @DistanceFactor ) ) );
	SET @F2 = @B2 * ( 1 - POWER( LOG( @D2 ) / LOG( 360 ), @P * POWER( @BreakEvenDistance / @dZ, @DistanceFactor ) ) );
	SET @B  = 2 * ( ( @fZ * ( @F1 + @F2 ) ) / 2 ) - 1;
	RETURN @B;
END


