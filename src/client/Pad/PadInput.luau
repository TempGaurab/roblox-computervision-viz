--!strict
-- Turns mouse and touch input on the pad surface into strokes, in unit pad space. Only the finger that
-- started a stroke is tracked. Input keeps being tracked off the pad until release; Strokes clamps it.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Cleanup = require(script.Parent.Parent.Cleanup)

export type Callbacks = {
	onBegin: (x: number, y: number) -> (),
	onMove: (x: number, y: number) -> (),
	onEnd: () -> (),
}

local PadInput = {}

-- Listens until `cleanup` runs. Ending that way also finishes any stroke in progress.
function PadInput.connect(surface: GuiObject, callbacks: Callbacks, cleanup: Cleanup.Cleanup)
	local mouseDown = false
	local activeTouch: InputObject? = nil

	local function unitPosition(input: InputObject): (number, number)
		local origin = surface.AbsolutePosition
		local size = surface.AbsoluteSize
		return (input.Position.X - origin.X) / size.X, (input.Position.Y - origin.Y) / size.Y
	end

	local function finish()
		if mouseDown or activeTouch ~= nil then
			mouseDown = false
			activeTouch = nil
			callbacks.onEnd()
		end
	end

	Cleanup.connect(
		cleanup,
		surface.InputBegan:Connect(function(input: InputObject)
			if mouseDown or activeTouch ~= nil then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				mouseDown = true
			elseif input.UserInputType == Enum.UserInputType.Touch then
				activeTouch = input
			else
				return
			end
			callbacks.onBegin(unitPosition(input))
		end)
	)

	Cleanup.connect(
		cleanup,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			local isActiveMouse = mouseDown and input.UserInputType == Enum.UserInputType.MouseMovement
			if isActiveMouse or (activeTouch ~= nil and input == activeTouch) then
				callbacks.onMove(unitPosition(input))
			end
		end)
	)

	Cleanup.connect(
		cleanup,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			local isActiveMouse = mouseDown and input.UserInputType == Enum.UserInputType.MouseButton1
			if isActiveMouse or (activeTouch ~= nil and input == activeTouch) then
				finish()
			end
		end)
	)

	-- The release never reaches us once the Roblox menu or another window has the input, so end the
	-- stroke now. Otherwise it would keep drawing with no button held.
	Cleanup.connect(cleanup, GuiService.MenuOpened:Connect(finish))
	Cleanup.connect(cleanup, UserInputService.WindowFocusReleased:Connect(finish))

	Cleanup.addTask(cleanup, finish)
end

return PadInput
