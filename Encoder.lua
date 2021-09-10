local DataCompressionMethods = {};

local Bits = Vector2.new(
	0b0000_0000_1111_1111,
	0b1111_1111_0000_0000
);

local math_floor = math.floor;
local math_atan2 = math.atan2;
local math_asin = math.asin;

local bit32_band = bit32.band;
local bit32_lshift = bit32.lshift;
local bit32_extract = bit32.extract;

local typeof = typeof;

DataCompressionMethods.Vector3 = {} do
	local VECTORMULTIPLER = 5;
	
	local function roundVector(vector)
		return Vector3.new(
			math_floor(VECTORMULTIPLER*vector.X + 0.5),
			math_floor(VECTORMULTIPLER*vector.Y + 0.5),
			math_floor(VECTORMULTIPLER*vector.Z + 0.5)
		);
	end;
	
	local function xyBits(n1, n2)
		return bit32_band(n1, Bits.X) + bit32_band(bit32_lshift(n2, 8), Bits.Y);
	end;
	
	function DataCompressionMethods.Vector3.Encode(vector)
		local vector = roundVector(vector);
		
		return Vector2int16.new(
			xyBits(vector.X, vector.Y),
			xyBits(vector.Z, VECTORMULTIPLER)
		);
	end;
	
	function DataCompressionMethods.Vector3.Decode(vector)
		local x, y = vector.X, vector.Y;
		local multiplier = bit32_extract(y, 8, 8);
		
		return Vector3.new(
			bit32_extract(x, 0, 8),
			bit32_extract(x, 8, 8),
			bit32_extract(y, 0, 8)
		)/multiplier;
	end;
	
	DataCompressionMethods.Vector3.EncodeType = "Vector3";
	DataCompressionMethods.Vector3.DecodeType = "Vector2int16";
end;

DataCompressionMethods.CFrame = {} do
	function DataCompressionMethods.CFrame.Encode(cframe)
		local sx, sy, sz, m00, m01, m02, m10, m11, m12, m20, m21, m22 = cframe:GetComponents();
		
		local Position = Vector3.new(sx, sy, sz);
		local Orientation do
			local ox = math_atan2(-m12, m22);
			local oy = math_asin(m02);
			local oz = math_atan2(-m01, m00);
			
			Orientation = Vector3.new(ox, oy, oz);
		end;
		
		return {
			DataCompressionMethods.Encode(Position),
			DataCompressionMethods.Encode(Orientation),
		};
	end;
	
	function DataCompressionMethods.CFrame.Decode(cframe)
		local Position = DataCompressionMethods.Decode(cframe[1]);
		local Orientation = DataCompressionMethods.Decode(cframe[2]);
		
		return CFrame.lookAt(Position, Orientation);
	end;
	
	DataCompressionMethods.CFrame.EncodeType = "CFrame";
	DataCompressionMethods.CFrame.DecodeType = "table";
end;

DataCompressionMethods.string = {} do
	
end;

local function InheritCallback(data, prefix)
	local dataType = typeof(data);
	local compressionMethod = DataCompressionMethods[dataType];
	local validType = string.format("%sType", prefix);
	
	assert(compressionMethod[validType] == dataType, "Invalid request.");
	
	return compressionMethod[prefix];
end;

function DataCompressionMethods.Encode(data)
	return InheritCallback(data, "Encode")(data);
end;

function DataCompressionMethods.Decode(data)
	return InheritCallback(data, "Decode")(data);
end;

return DataCompressionMethods;
