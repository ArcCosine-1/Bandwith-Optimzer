local CharacterController = {};
CharacterController.__index = CharacterController;

local PathfindingService = game:GetService("PathfindingService");

local Encoder = require(script.Parent);
local Lerp = require(script:WaitForChild("Lerp"));
local Signal = require(script.Parent:WaitForChild("Signal"));

local function assert(condition, pattern, ...)
	return condition == false and error(string.format(pattern, ...), 2);
end;

function CharacterController.new(model)
	assert(model:FindFirstChildWhichIsA("Humanoid") ~= nil, "Invalid model.");
	
	local self = setmetatable({}, CharacterController);
	
	self.Character = model;
	self.Primary = model.HumanoidRootPart;
	
	self.MoveToFinished = Signal.new("MoveToFinished");
	
	self.DestinationChanged = Signal.new("DestinationChanged");
	self.Destination = CFrame.new();
	
	coroutine.wrap(CharacterController._init)(self);
	
	return self;
end;

function CharacterController:_init()
	self.Primary.Anchored = true;
	
	self.DestinationChanged:Connect(function()
		local destination = self.Destination;
		self:_moveTo(destination);
	end);
	
	local animator = self.Character:FindFirstChild("Animator");
	if animator ~= nil then
		animator.Enabled = false;
	end;
end;

function CharacterController:_getLegHeight()
	local character = self.Character;
	local isR15 = character.Humanoid.RigType == Enum.HumanoidRigType.R15;
	
	local legPieces = {
		isR15 and character.RightLowerLeg or character["Right Leg"],
		isR15 and character.LeftLowerLeg or character["Left Leg"],
	};
	
	return (legPieces[1].Position.Y + legPieces[2].Position.Y)/2
end;

function CharacterController:_requiresPathfinding(destination)
	local destination = destination.Position;
	
	local lY = self:_getLegHeight();
	local dY = destination.Y;
	
	return lY < dY or lY > dY;
end;

function CharacterController:_createPath(destination)
	local char = self.Character;
	local charSize = char:GetExtentsSize();
	
	local path = PathfindingService:CreatePath{
		AgentRadius = charSize.X/2,
		AgentHeight = charSize.Y,
		AgentCanJump = char.Humanoid.JumpPower > 0,
	};
	
	path:ComputeAsync(self.Primary.Position, destination.Position);
	return path;
end;

function CharacterController:_moveTo(destination)
	local connection = nil;
	local cancelled = false;
	
	local cachedLerps = {};
	
	local function moveTo()
		local character = self.Character;
		local primary = self.Primary;
		
		local lerpObj = Lerp.new(primary.CFrame, destination, 0.1);
		table.insert(cachedLerps, lerpObj);
		lerpObj:Play();
		
		lerpObj.CFrameChanged:Connect(function()
			if cancelled == true then
				lerpObj:Destroy();
				return;
			end;
			local newCF = lerpObj.CFrame;
			character:SetPrimaryPartCFrame(newCF);
		end);
		
		lerpObj.Completed:Wait();
	end;
	
	connection = self.DestinationChanged:Connect(function()
		local newDestination = self.Destination;
		
		if newDestination ~= destination then 
			connection:Disconnect();
			cancelled = true;
		end;
	end);
	
	if self:_requiresPathfinding(destination) then
		local path = self:_createPath(destination);
		local waypoints = nil;
		
		local elapsed = os.time();
		
		if path.Status == Enum.PathStatus.Success then
			waypoints = path:GetWaypoints();
			
			for _, waypoint in pairs(waypoints) do
				if cancelled == true then
					break;
				end;
				
				moveTo(CFrame.new(waypoint.Position));
			end;
			
			self.MoveToFinished:Fire(os.time() - elapsed);
		end;
	else
		local elapsed = os.time();
		moveTo(destination)
		self.MoveToFinished:Fire(os.time() - elapsed);
	end;
	
	for _, object in pairs(cachedLerps) do
		object:Destroy();
	end;
	cancelled = true;
end;

function CharacterController:MoveTo(destination)
	self.Destination = destination;
	self.DestinationChanged:Fire();
end;

return CharacterController;
