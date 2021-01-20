local addonName, Addon = ...
local parentAddon = _G[Addon.parent]
local AuraModule, AuraFrame = parentAddon:NewModule('Debuff'), parentAddon:CreateClass('Frame', parentAddon.Frame)

function AuraModule:Load()
	self.frame = AuraFrame:New("debuff")
end

function AuraModule:Unload()
	self.frame:Free()
end

function AuraFrame:New(name)
	local f = AuraFrame.proto.New(self, name)
	f:SetFrameStrata('LOW')
	Addon:New(f, "Debuffs")
	return f
end

function AuraFrame:GetDefaults()
	return {
		scale = 1,
		point = 'CENTER',
		y = 150,
		x = 0,
		spacing = 0,
		columns = 10,
		rows = 2,
		isRightToLeft = false,
		isBottomToTop = false,
		method = 1, --time, index or name
		direction = true,
		padding = 0,
		textOffset = 0,
		anchorText = "Bottom",
		textX = 0,
		textY = 0,
	}
end

function AuraFrame:GetFilter()
	return "HARMFUL"
end
