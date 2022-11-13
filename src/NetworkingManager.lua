-------------------------------
--- // MODULE DEFINITION // ---
-------------------------------

local NetworkingManager : any? = {};
NetworkingManager.__index = NetworkingManager;

------------------------------
--- // TYPE DEFINITIONS // ---
------------------------------

type Array<ValueType> = {[number]: ValueType};
type Dictionary<KeyType, ValueType> = {[KeyType]: ValueType};
type GenericFunction = (...any?) -> (...any?);

type NetworkConnection = {
	Callback : GenericFunction,
	DoDestroy : boolean,
	Index : number,
	Disconnect : (NetworkConnection) -> (),
	Next : NetworkConnection,
};

type NetworkingManager = {
	Networks : Dictionary<string, Network>,
};

type Network = {
	NetworkBinding : string,
	RemoteEvent : RemoteEvent,
	Connections : Array<NetworkConnection>,
	ConnectionsHead : NetworkConnection?,
	ConnectionsAmount : number,
	DoEndCycle : boolean,
	RBXScriptConnection : RBXScriptConnection,
	FilterTypes : Array<string>,
	NetworkFilterType : string,
	Manager : NetworkingManager,
	Debounce : number?,
	Time : Dictionary<Player, number> | number | nil
};

export type NetworkConnection = NetworkConnection;
export type Network = Network;
export type NetworkingManager = NetworkingManager;

-----------------------------
--- // ROBLOX SERVICES // ---
-----------------------------

local RunService = game:GetService("RunService");
local Players = game:GetService("Players");

-----------------------
--- // VARIABLES // ---
-----------------------

local IsServer : boolean = RunService:IsServer();
local IsStudio : boolean = RunService:IsStudio();
local ConnectionName : string = ("On%sEvent"):format(IsServer and "Server" or "Client");

local FreeRunnerThread : thread? = nil;

local LocalPlayer : Player? = IsServer == false and (Players.LocalPlayer or Players.PlayerAdded:Wait()) or nil;

-----------------------
--- // FUNCTIONS // ---
-----------------------

local function assert(Condition : boolean, Pattern : string, ... : any)
	if (Condition == false) then
		if (select("#", ...) > 0) then
			Pattern = Pattern:format(...);
		end;
		error(Pattern, 2);
	end;
end;

local function RunnerThread(Callback : GenericFunction, ... : any)
	local AcquiredRunnerThread = FreeRunnerThread;
	FreeRunnerThread = nil;
	Callback(...);

	FreeRunnerThread = AcquiredRunnerThread;
end;

local function RunFreeThread(... : any)
	RunnerThread(...);
	while (true) do
		RunnerThread(coroutine.yield());
	end;
end;

local MakeEnum : any? do
	local ErrorFormat : string = "%s is not a valid member of %q";
	local EnumFormat : string = "Enum.%s";

	MakeEnum = function(EnumName : string, EnumItems : Array<string>)
		local _Enum = {};

		for _, EnumItem : string in ipairs(EnumItems) do
			_Enum[EnumItem] = EnumItem;
		end;

		local EnumFormat : string = EnumFormat:format(EnumName);

		return (setmetatable(_Enum, {
			__index = function(_, Key : string)
				error(ErrorFormat:format(Key, EnumFormat), 2);
			end,
			__newindex = function(_, Key : string)
				error(ErrorFormat:format(Key, EnumFormat), 2);
			end,
			__metatable = function() : nil
				return (nil);
			end,
		}));
	end;
end;

---------------------
--- // MODULES // ---
---------------------

local Network : any? do
	local DebounceLeeway : number = 2;

	local function IsAlive(Character : Model) : boolean
		local Humanoid : Humanoid = Character.Humanoid;
		return (Character ~= nil and Humanoid.Health > 0 and Humanoid:GetStateType() ~= Enum.HumanoidStateType.Dead);
	end;

	local function GetTransform(... : any) : (Player) -> (Player, ...any?)?
		if (select("#", ...) ~= 2) then
			return;
		end;

		local Player : Player, Transform : GenericFunction = select(2, ...);
		if (type(Transform) == "function") then
			return function(Player : Player) : any
				return (Player), (Transform(Player));
			end;
		end;
	end;

	Network = {};
	Network.__index = Network;
	
	function Network.new(Manager : NetworkingManager, NetworkBinding : string, RemoteEvent : RemoteEvent?) : Network
		local self = {};
		
		self.NetworkBinding = NetworkBinding;
		self.RemoteEvent = RemoteEvent or Instance.new("RemoteEvent");

		self.Connections = {};
		self.ConnectionsHead = nil;
		self.ConnectionsAmount = 0;
		self.DoEndCycle = false;

		self.FilterTypes = nil;
		self.NetworkFilterType = NetworkingManager.NetworkFilterType.Whitelist;

		self.Debounce = nil;
		self.NetworkDebounceType = NetworkingManager.NetworkDebounceType.WaitUntil;

		Manager.Networks[NetworkBinding] = self;
		self.Manager = Manager;

		setmetatable(self, Network);
		self:MakeHandler();

		return (self);
	end;

	function Network:_connect(Callback : GenericFunction) : NetworkConnection
		if (self.ConnectionsAmount == nil) then
			self.ConnectionsAmount = 0;
		end;
		local TotalConnections : number = self.ConnectionsAmount;

		local Information : Dictionary<string, any> = {
			Callback = Callback,
			Index = TotalConnections + 1,
			
			Disconnect = function(_self)
				table.remove(self.Connections, _self.Index);
				self.ConnectionsAmount = self.ConnectionsAmount - 1;

				for Key : string in pairs(_self) do
					_self[Key] = nil;
				end;

				_self = nil;

				for i = 1, self.ConnectionsAmount do
					local Connection = self.Connections[i];
					if (i > 1) then
						self.Connections[i - 1].Next = Connection;
					end;
					Connection.Index = i;
				end;
			end,
		};

		if (TotalConnections == 0) then
			self.ConnectionsHead = Information;
		else
			self.Connections[TotalConnections].Next = Information;
		end;

		table.insert(self.Connections, Information);
		return (Information);
	end;

	function Network:Connect(Callback : GenericFunction) : NetworkConnection
		return (self:_connect(Callback));
	end;

	function Network:Print() : NetworkConnection
		return (self:_connect(print));
	end;

	function Network:Once(Callback : GenericFunction) : NetworkConnection
		local Connection : NetworkConnection = nil;
		
		Connection = self:_connect(function(...)
			coroutine.wrap(Connection.Disconnect, Connection)
			Callback(...);
		end);
		
		return (Connection);
	end;

	function Network:Fire(... : any)
		local RemoteEvent : RemoteEvent = self.RemoteEvent;

		if (IsServer == true) then
			local Transform : GenericFunction? = GetTransform(...);
			if (Transform == nil) then
				RemoteEvent:FireClient(Transform());
			else
				RemoteEvent:FireClient(...);
			end;
		else
			RemoteEvent:FireServer(...);
		end;
	end;

	function Network:FireAll(... : any)
		assert(IsServer == true, "This method can only be called on the server.");
		self.RemoteEvent:FireAllClients(...);
	end;

	function Network:FireWithTransform(Players : Array<Player>, Transform : (Player) -> (...any?))
		assert(IsServer == true, "This method can only be called on the server.");
		for _, Player : Player in ipairs(Players) do
			Network.Fire(self, Transform(Player));
		end;
	end;

	function Network:FireAlive(... : any)
		local Transform : GenericFunction? = GetTransform(...);

		for _, Player : Player in ipairs(Players:GetPlayers()) do
			if (IsAlive(Player.Character) == false) then
				break;
			end;

			if (Transform ~= nil) then
				Network.Fire(self, Transform(Player));
			else
				Network.Fire(self, Player, ...);
			end;
		end;
	end;

	function Network:FireAllInRage(Origin : Vector3, Range : number, ... : any)
		for _, Player : Player in ipairs(Players:GetPlayers()) do
			local Character : Model = Player.Character;

			if (IsAlive(Character) == false) then
				break;
			end;

			local Distance = (Origin - Character.HumanoidRootPart.Position).Magnitude;
			if (Distance <= Range) then
				Network.Fire(self, Player, ...);
			end;
		end;
	end;

	function Network:IsValidType(Item : any) : boolean
		local Type : string = typeof(Item);
		local ContainsType : boolean = table.find(self.FilterTypes, Type) ~= nil;

		if (ContainsType == false and Type == "Instance" and table.find(self.FilterTypes, Item.ClassName)) then
			ContainsType = true;
		end;

		if (self.NetworkFilterType == NetworkingManager.NetworkFilterType.Whitelist and ContainsType == true) then
			return (true);
		elseif (self.NetworkFilterType == NetworkingManager.NetworkFilterType.Blacklist and ContainsType == false) then
			return (true);
		end;

		return (false);
	end;

	function Network:MakeDebounce(DebounceLength : number)
		if (self.Debounce ~= nil) then
			warn("Previous debounce is being overwritten.");
		end;

		self.Debounce = DebounceLength;
		self.Time = IsServer == true and { } or os.time();
		
		if (self.NetworkDebounceType == NetworkingManager.NetworkDebounceType.MeetQuota and IsServer == true) then
			self.IsSafe = {};
		end;
	end;
	
	function Network:UpdateDebounce(Player : Player?)
		assert(self.Debounce ~= nil, "No debounce has been initialized.", 2);
		
		if (IsServer == true) then
			self.Time[Player] = os.time();
		else
			self.Time = os.time();
		end;
	end;
	
	function Network:UnregisterPlayer(Player : Player)
		if (type(self.Time) == "table") then
			self.Time[Player] = nil;
			
			if (self.IsSafe ~= nil) then
				self.IsSafe[Player] = nil;
			end;
		end;
	end;

	function Network:IsDebounceActive(Player : Player?) : (boolean, number?)
		if (self.Debounce == nil) then
			return (false);
		end;
		
		local LastCheck : number = self.Time;
		if (IsServer == true) then
			if (LastCheck[Player] == nil) then
				LastCheck[Player] = os.time();
				return (false);
			end;
			
			LastCheck = LastCheck[Player];
		end;
		
		local DebounceLength : number = self.Debounce;
		local ElapsedTime : number = os.time() - LastCheck;

		if (self.NetworkDebounceType == NetworkingManager.NetworkDebounceType.MeetQuota) then
			self.IsSafe[Player] = ElapsedTime - DebounceLeeway < DebounceLength;
			Network.UpdateDebounce(self, Player);
			return (false);
		end;
		
		if (ElapsedTime + DebounceLeeway < DebounceLength) then
			return (true), (ElapsedTime);
		end;

		return (false);
	end;
	
	function Network:DoCycle(Rate : number, PrepareData : () -> (...any?))
		assert(self.Rate == nil, "Cycle already exists.");
		
		local DoWait : boolean = typeof(Rate) == "RBXScriptSignal";
		self.DoEndCycle = false;
		self.Rate = Rate;
		
		coroutine.wrap(function()
			while (self.DoEndCycle == false) do
				if (DoWait == true) then
					Rate:Wait();
				else
					task.wait(self.Rate);
				end;
				
				Network.Fire(self, PrepareData());
			end;
		end)();
	end;
	
	function Network:EndCycle()
		assert(self.Rate ~= nil, "No cycle is currently running.");
		
		self.DoEndCycle = true;
		self.Rate = nil;
	end;
	
	function Network:Disable()
		if (self.RBXScriptConnection ~= nil) then
			self.RBXScriptConnection:Disconnect();
		end;
		
		if (IsServer == true and self.Debounce ~= nil) then
			for Player : Player in pairs(self.Time) do
				self.Time[Player] = nil;
			end;
			
			if (self.IsSafe ~= nil and self.NetworkDebounceType == NetworkingManager.NetworkDebounceType.MeetQuota) then
				for Player : Player in pairs(self.IsSafe) do
					self.IsSafe[Player] = nil;
				end;
			end;
			
			self.Time, self.IsSafe = nil, nil;
		end;
		
		for Index : number, NetworkConnection : NetworkConnection in pairs(self.Connections) do
			for Key : string in pairs(NetworkConnection) do
				NetworkConnection[Key] = nil;
			end;
			self.Connections[Index] = nil;
		end;
		
		self.Connections = nil;
		
		for Key : string in pairs(self) do
			self[Key] = nil;
		end;
		
		self = nil;
	end;
	
	function Network:Suspend(): GenericFunction
		assert(self.RBXScriptConnection ~= nil, "Network must contain \"RBXScriptConnection\"");
		
		self.RBXScriptConnection:Disconnect();
		return (function()
			self:MakeHandler();
		end);
	end;
	
	function Network:MakeHandler()
		self.RBXScriptConnection = self.RemoteEvent[ConnectionName]:Connect(function(... : any)
			local Player : Player? = IsServer == true and select(1, ...) or nil;
			local IsDebounceActive : boolean, ElapsedTime : number? = self:IsDebounceActive(Player);
			
			if (IsDebounceActive == true) then
				error(("Requested rejected, %d seconds remaining"):format(math.floor(ElapsedTime)), 2);
			end;

			if (self.IsSafe ~= nil) then
				assert(self.IsSafe[Player] == true, "User is unsafe.");
			end;

			local ArgsLength : number = select("#", ...);
			if (type(self.FilterTypes) == "table" and ArgsLength > 0) then
				local NetworkFilterType : string = self.NetworkFilterType;
				local Packed : Array<any> = { ... };

				for Index : number, Arg : any in ipairs(Packed) do
					assert(self:IsValidType(Arg) == true, "invalid argument #%d to %q.", Index, self.NetworkBinding);
				end;
			end;

			local ConnectionInformation : NetworkConnection = self.ConnectionsHead;

			while (ConnectionInformation ~= nil) do
				if (FreeRunnerThread == nil) then
					FreeRunnerThread = coroutine.create(RunFreeThread);
				end;

				task.spawn(FreeRunnerThread, ConnectionInformation.Callback, ...);
				ConnectionInformation = ConnectionInformation.Next;
			end;

			pcall(Network.UpdateDebounce, self, Player);
		end);
	end;
end;

----------------------------
--- // ENCODING UTILS // ---
----------------------------

local MaxBase : number = 32;
local SplitCharacter : string = string.char(MaxBase + 4);

local OrientationMultiplier : number = 100;
local CoordMultiplier : number = 5;

local PrefixesOut : Array<Array<string>> = {
	[1] = {
		[1] = "", --Both numbers are positive
		[-1] = string.char(MaxBase + 2) -- Only the second number is negative
	};
	[-1] = {
		[1] = string.char(MaxBase + 1), -- Only the first number is negative
		[-1] = string.char(MaxBase + 3) -- Both numbers are negative
	};
};

local PrefixesIn : Dictionary<string, Array<number>> = {
	[PrefixesOut[1][-1]] = {1, -1},
	[PrefixesOut[-1][1]] = {-1, 1},
	[PrefixesOut[-1][-1]] = {-1, -1}
};

local function GetPrefix(A : number, B : number) : string
	if (math.floor(A) == 0) then
		A = 1;
	elseif (math.floor(B) == 0) then
		B = 1;
	end;

	return PrefixesOut[math.sign(A)][math.sign(B)];
end;

local function GetMultiplier(Prefix : string) : (number, number)
	local Pair : Array<number>? = PrefixesIn[Prefix];

	if (Pair == nil) then
		return (1), (1);
	else
		local ASign, BSign = unpack(Pair, 1, 2);
		return (ASign), (BSign);
	end;
end;

local function FindPrefix(Encoded : string) : string?
	local Prefix : string = Encoded:sub(1, 1);
	
	if (PrefixesIn[Prefix] ~= nil) then
		return (Prefix);
	end;
end;

local function EncodeWithBase(Decimal : number, Base : number) : string
	local Base : number = math.clamp(Base, 2, MaxBase);

	local Divisor : number = 1/Base;
	local OutputString : string = "";

	while (Decimal >= 1) do
		local Remainder : number = Decimal % Base;
		Decimal = math.floor(Decimal*Divisor);
		OutputString ..= string.char(Remainder);
	end;

	return (OutputString:reverse());
end;

local function DecodeWithBase(Encoded : string, Base : number, Prefix : string) : (number, number?, number?)
	local ASign : number?, BSign : number?;
	local Base : number = math.clamp(Base, 16, MaxBase);
	local Length : number = Encoded:len();

	if (Prefix ~= nil) then
		Encoded = Encoded:sub(2, Length);
		Length = Length - 1;
		
		ASign, BSign = GetMultiplier(Prefix);
	end;

	local Decimal : number = 0;

	for pos = 1, Length do
		local Byte : number = Encoded:sub(pos, pos):byte();
		local Next : number = (Base^(Length - pos))*Byte;

		Decimal += Next;
	end;

	return (Decimal), (ASign), (BSign);
end;

local function Combine(A : number, B : number) : number
	return (bit32.band(A, 255) + bit32.band(bit32.lshift(B, 8), 65280));
end;

local function Extract(Combined : number, ASign : number, BSign : number) : (number, number)
	return (ASign*bit32.extract(Combined, 0, 8)), (BSign*bit32.extract(Combined, 8, 8));
end;

local function ExtractIntoDatatype(
	Combined : number, ASign : number, BSign : number, 
	Datatype : {new : (...number?) -> (any)}, Constructor : string?
) : any
	local X : number, Y : number = Extract(Combined, ASign, BSign);
	if (Constructor ~= nil) then
		return (Datatype[Constructor](X/CoordMultiplier, Y/CoordMultiplier));
	end;
	return (Datatype.new(X/CoordMultiplier, Y/CoordMultiplier));
end;

local function RoundVector(Vector : Vector2 | Vector3) : (number, number, number?)
	local X : number = math.floor(CoordMultiplier*Vector.X + 0.5);
	local Y : number = math.floor(CoordMultiplier*Vector.Y + 0.5);
	local Z : number? = nil;
	
	if (typeof(Vector) == "Vector3") then
		Z = math.floor(CoordMultiplier*Vector.Z + 0.5);
	end;
	
	return (X), (Y), (Z);
end;

-------------------
--- // ENUMS // ---
-------------------

NetworkingManager.NetworkFilterType = MakeEnum("NetworkFilterType", {
	"Whitelist",
	"Blacklist",
});

NetworkingManager.NetworkDebounceType = MakeEnum("NetworkDebounceType", {
	"WaitUntil",
	"MeetQuota" 
});

-------------------------
--- // COMPRESSION // ---
-------------------------

NetworkingManager.Compress, NetworkingManager.Decompress = {}, {};

function NetworkingManager.Compress.Vector2(Vector : Vector2, CompressionBase : number?) : string
	local X : number, Y : number = RoundVector(Vector);
	return (GetPrefix(X, Y) .. EncodeWithBase(Combine(math.abs(X), math.abs(Y)), CompressionBase or MaxBase));
end;

function NetworkingManager.Decompress.Vector2(EncodedVector : string, CompressionBase : number?) : Vector2
	local Prefix : string? = FindPrefix(EncodedVector);
	local Combined : number, ASign : number, BSign : number = DecodeWithBase(
		EncodedVector, 
		CompressionBase or MaxBase, 
		Prefix
	);
	
	return (ExtractIntoDatatype(Combined, ASign, BSign, Vector2));
end;

function NetworkingManager.Compress.GridPosition(Position : Vector2, Rotation : number, CompressionBase : number?) : string
	local CompressionBase : number = CompressionBase or MaxBase;
	
	local X : number, Y : number = RoundVector(Position	);
	local CompressedPosition : string = GetPrefix(X, Y) .. EncodeWithBase(
		Combine(math.abs(X), math.abs(Y)), 
		CompressionBase
	);
	
	local CompressedRotation : string = EncodeWithBase(math.floor(OrientationMultiplier * Rotation + 0.5), CompressionBase);
	
	return (CompressedPosition .. SplitCharacter .. CompressedRotation);
end;

function NetworkingManager.Decompress.GridPosition(EncodedData : string, Axis : Vector3?, CompressionBase : number?) : CFrame
	local Axis : Vector3 = Axis or Vector3.new(0, 1, 0);
	local CompressionBase : number = CompressionBase or MaxBase;
	
	local Data : Array<string> = EncodedData:split(SplitCharacter);
	local EncodedPosition : string, EncodedRotation : string = Data[1], Data[2];
	
	local Position : CFrame? do
		local Prefix : string = FindPrefix(EncodedPosition);
		local Combined : number, ASign : number, BSign : number = DecodeWithBase(
			EncodedPosition, 
			CompressionBase, 
			Prefix
		);
		
		local X : number = (bit32.extract(Combined, 0, 8)*ASign)/CoordMultiplier;
		local Z : number = (bit32.extract(Combined, 8, 8)*BSign)/CoordMultiplier;
		
		Position = CFrame.new(X, 0, Z);
	end;
	
	local Rotation : number = DecodeWithBase(EncodedPosition, CompressionBase)/OrientationMultiplier;
	
	return (Position*CFrame.fromAxisAngle(Axis, Rotation));
end;

---------------------
--- // METHODS // ---
---------------------

function NetworkingManager._new() : NetworkingManager
	local self : NetworkingManager = {};

	self.Networks = {};

	return (setmetatable(self, NetworkingManager));
end;

function NetworkingManager.new() : NetworkingManager
	return (NetworkingManager._new());
end;

function NetworkingManager.fromRemote(RemoteEvent : RemoteEvent) : NetworkingManager
	local NetworkingManager : NetworkingManager = NetworkingManager._new();
	NetworkingManager:CreateNetwork(RemoteEvent.Name, RemoteEvent);

	return (NetworkingManager);
end;

function NetworkingManager.fromRemotesList(RemoteEventsList : Array<RemoteEvent>) : NetworkingManager
	local NetworkingManager : NetworkingManager = NetworkingManager._new();

	for _, RemoteEvent : RemoteEvent in ipairs(RemoteEventsList) do
		NetworkingManager:CreateNetwork(RemoteEvent.Name, RemoteEvent);
	end;

	return (NetworkingManager);
end;

function NetworkingManager.positionValidator(
	RemoteEvent : RemoteEvent?, 
	DebounceLength : number?, 
	MagnitudeLeeway : number?
) : NetworkingManager
	local Manager : NetworkingManager = NetworkingManager._new();
	local Network : Network = Manager:CreateNetwork("PositionValidator", RemoteEvent);
	
	local DebounceLength : number = DebounceLength or 5;
	local MagnitudeLeeway : number = MagnitudeLeeway or 2;
	
	Network.NetworkDebounceType = NetworkingManager.NetworkDebounceType.MeetQuota;
	Network:MakeDebounce(DebounceLength);
	
	if (IsServer == true) then
		local Positions : Dictionary<Model, Vector2> = {};
		Network:Connect(function(Player : Player, Position : string)
			local Character : Model = Player.Character;
			
			if (Character == nil) then
				return;
			end;
			
			local Position : Vector2 = NetworkingManager.Decompress.Vector2(Position);
			
			local RealPosition : Vector2 do
				local Pivot : Vector3 = Character:GetPivot().Position;
				RealPosition = Vector2.new(Pivot.X, Pivot.Z);
			end;

			if (IsStudio == true) then
				print(("Real Position: %s\nClient Position: %s"):format(tostring(RealPosition), tostring(Position)));
			end;

			if ((RealPosition - Position).Magnitude > MagnitudeLeeway) then
				Network.IsSafe[Player] = false;
				return;
			end;
			
			local LastPosition : Vector2 = Positions[Character];
			local PossibleDistance : number = Character.Humanoid.WalkSpeed*DebounceLength;
			
			if (LastPosition ~= nil) then
				local Traversed : number = (LastPosition - Position).Magnitude - MagnitudeLeeway;
				
				if (Traversed <= PossibleDistance) then
					Positions[Character] = Position;
				else
					Network.IsSafe[Player] = false;
				end;
			elseif (LastPosition == nil) then
				Positions[Character] = RealPosition;
			else
				Network.IsSafe[Player] = false;
			end
		end);
	else
		Network:DoCycle(DebounceLength, function()
			local Pivot : Vector3 = LocalPlayer.Character:GetPivot().Position;
			local FlatPosition : Vector2 = Vector2.new(Pivot.X, Pivot.Z);
			
			return (NetworkingManager.Compress.Vector2(FlatPosition));
		end);
	end;
	
	return (Manager);
end;

function NetworkingManager:CreateNetwork(NetworkBinding : string, RemoteEvent : RemoteEvent?) : Network
	local NewNetwork : Network = Network.new(self, NetworkBinding, RemoteEvent);
	return (NewNetwork);
end;

function NetworkingManager:GetNetwork(NetworkBinding : string) : Network
	local Network = self.Networks[NetworkBinding];
	assert(Network ~= nil, "Network, %q, does not exist.", NetworkBinding);

	return (Network);
end;

function NetworkingManager:WipePlayerFromNetworks(Player : Player)
	assert(IsServer, "Method can only be used on the server.");
	
	for _, Network : Network in pairs(self.Networks) do
		Network:UnregisterPlayer(Player);
	end;
end;

-----------------
--- // END // ---
-----------------

return (NetworkingManager);
