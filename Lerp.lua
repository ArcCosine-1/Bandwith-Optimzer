local Lerp = {};
Lerp.__index = Lerp;

local RunService = game:GetService("RunService");

local MainModule = script:FindFirstAncestor("RoSoft.Character");
local Signal = require(MainModule:WaitForChild("Signal"));

local IsServer = RunService:IsServer();
local Stepper = IsServer == true and RunService.Heartbeat or RunService.RenderStepped;

function Lerp.new(beginning, destination, step)
	local self = setmetatable({}, Lerp);

	self.Destination = destination;
	self.Beginning = beginning;
	self.Step = step;

	self.CurrentIndex = 0;

	self.State = "Paused";
	self.StateChanged = Signal.new("StateChanged");

	self.CFrame = beginning;
	self.CFrameChanged = Signal.new("CFrameChanged");
	
	self.Completed = Signal.new("Completed");

	return self;
end;

function Lerp:Play()
	-->		Create lerping state machine
	self.State = "Playing";

	local connection = nil;
	local function disconnect()
		connection:Disconnect();
	end;
	local lerpCancelled = false;

	connection = self.StateChanged:Connect(function()
		local newState = self.State;

		if newState == "Paused" then
			disconnect();
			lerpCancelled = true;
		elseif newState == "Stopped" then
			disconnect()
		else
			disconnect();
		end;
	end);

	-->		Begin lerping from paused state
	for i = self.CurrentIndex, 1, self.Step do
		if lerpCancelled == true then
			break;
		end;

		self.CFrame = self.Beginning:Lerp(self.Destination, i);
		self.CFrameChanged:Fire();

		Stepper:Wait();
	end;

	-->		Reset current index if lerp wasn't stopped by a pause
	if lerpCancelled == false then
		self:Stop();
	end;
	
	self.Completed:Fire();
end;

function Lerp:Pause()
	self.State = "Paused";
	self.StateChanged:Fire();
end;

function Lerp:Stop()
	self.State = "Stopped";
	task.defer(function()
		self.CurrentIndex = 0;
	end);
	self.StateChanged:Fire();
end;

function Lerp:Destroy()
	pcall(function()
		for index, value in pairs(self) do
			if type(value) == "table" then
				index[value]:Destroy();
			end;
			index[value] = nil;
		end;
	end);
end;

return Lerp;
