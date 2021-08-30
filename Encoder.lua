local Encoder = {};

local Debris = game:GetService("Debris");

local POSITION_MULTIPLIER = 5;
local Bits = Vector2.new(
	0b0000_0000_1111_1111,
	0b1111_1111_0000_0000
);

local function roundVector(vector, bit: number)
	if bit == 0 then
		return Vector3.new(
			math.floor(POSITION_MULTIPLIER*vector.X + 0.5),
			math.floor(POSITION_MULTIPLIER*vector.Y + 0.5),
			math.floor(POSITION_MULTIPLIER*vector.Z + 0.5)
		);
	elseif bit == 1 then
		return Vector2.new(
			math.floor(POSITION_MULTIPLIER*vector.X + 0.5),
			math.floor(POSITION_MULTIPLIER*vector.Y + 0.5)
		);
	else
		error("Bit not accepted", 2);
	end;
end;

local function xyBits(n1, n2)
	return bit32.band(n1, Bits.X) + bit32.band(bit32.lshift(n2, 8), Bits.Y);
end;

function Encoder.EncodePositioningData(data)
	local dataType = typeof(data):lower();
	
	if dataType == "vector3" then
		local vector = roundVector(data, 0);
		
		return Vector3int16.new(
			xyBits(vector.X, vector.Y),
			xyBits(vector.Z, POSITION_MULTIPLIER)
		);
	elseif dataType == "vector2" then
		local vector = roundVector(data, 1);
		
		return Vector2int16.new(
			xyBits(vector.X, vector.Y),
			xyBits(vector.Z, POSITION_MULTIPLIER)
		);
	elseif dataType == "cframe" then
		local sx, sy, sz, m00, m01, m02, m10, m11, m12, m20, m21, m22 = CFrame:GetComponents();
		
		local Position = Vector3.new(sx, sy, sz);
		local Orientation do
			local X = math.atan2(-m12, m22);
			local Y = math.asin(m02);
			local Z = math.atan2(-m01, m00);
			
			Orientation = Vector3.new(X, Y, Z);
		end;
		
		return {
			Encoder.EncodePositioningData(Position),
			Encoder.EncodePositioningData(Orientation),
		};
	end;
end;

function Encoder.DecodePositioningData(data)
	local dataType = typeof(data):lower();
	
	if dataType == "vector3int16" then
		local x, y = data.X, data.Y;
		local multiplier = bit32.extract(y, 8, 8);
		
		return Vector3.new(
			bit32.extract(x, 0, 8),
			bit32.extract(x, 8, 8),
			bit32.extract(y, 0, 8)
		)/multiplier;
	elseif dataType == "vector2int16" then
		local x, y = data.X, data.Y;
		local multiplier = bit32.extract(y, 8, 8);

		return Vector2.new(
			bit32.extract(x, 0, 8),
			bit32.extract(x, 8, 8),
			bit32.extract(y, 0, 8)
		)/multiplier;
	elseif dataType == "table" then
		local position = dataType[1];
		local orientation = dataType[2];
		
		return CFrame.new(
			Encoder.DecodePositioningData(position), 
			Encoder.DecodePositioningData(orientation)
		);
	end;
end;

return Encoder;
