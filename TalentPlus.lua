-- TalentPlus: clicking a talent only plans it; nothing is learned until you
-- press Learn. Written for the 1.12.1 client (Lua 5.0, OctoWoW / Vanilla).

local TP = CreateFrame("Frame", "TalentPlusFrame")

local MAX_TALENT_BUTTONS = 100   -- buttons are TalentFrameTalent1..N; stop at the first missing one
local APPLY_TIMEOUT = 3          -- seconds to wait for the server to accept one rank
local PLAN_R, PLAN_G, PLAN_B = 0.2, 0.8, 1.0

local plan = {}                  -- ordered list of { tab = n, index = n }, one entry per rank
local applying = false
local applyTarget, applyTimer = 0, 0
local hooked = false
local learnButton, clearButton

local Refresh

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TalentPlus:|r " .. msg)
end

local function Error(msg)
	UIErrorsFrame:AddMessage(msg, 1.0, 0.1, 0.1, 1.0)
end

------------------------------------------------------------------------------
-- Plan simulation
------------------------------------------------------------------------------

-- Reads the real talent state from the client: ranks, tiers, points spent per
-- tree and a tier:column -> index lookup used to resolve prerequisites.
local function SnapshotTalents()
	local state = { tabs = {}, free = UnitCharacterPoints("player") or 0 }
	for tab = 1, GetNumTalentTabs() do
		local t = { spent = 0, talents = {}, grid = {} }
		for index = 1, GetNumTalents(tab) do
			local name, _, tier, column, rank, maxRank = GetTalentInfo(tab, index)
			t.talents[index] = { name = name, tier = tier, rank = rank, maxRank = maxRank }
			t.grid[tier .. ":" .. column] = index
			t.spent = t.spent + rank
		end
		state.tabs[tab] = t
	end
	return state
end

-- Returns nil if one more rank of the talent can be taken in this state,
-- otherwise the reason it can't.
local function CheckAdd(state, tab, index)
	local t = state.tabs[tab]
	local talent = t and t.talents[index]
	if not talent then
		return "Unknown talent."
	end
	if talent.rank >= talent.maxRank then
		return talent.name .. " is already at max rank."
	end
	if state.free <= 0 then
		return "You have no talent points left."
	end
	local needed = (talent.tier - 1) * 5
	if t.spent < needed then
		return string.format("Requires %d points in this tree.", needed)
	end
	local prereqs = { GetTalentPrereqs(tab, index) }
	for i = 1, table.getn(prereqs), 3 do
		local reqIndex = t.grid[prereqs[i] .. ":" .. prereqs[i + 1]]
		local req = reqIndex and t.talents[reqIndex]
		if req and req.rank < req.maxRank then
			return string.format("Requires %d points in %s.", req.maxRank, req.name)
		end
	end
end

local function TakeRank(state, tab, index)
	local t = state.tabs[tab]
	t.talents[index].rank = t.talents[index].rank + 1
	t.spent = t.spent + 1
	state.free = state.free - 1
end

-- Replays the steps on top of the real talents. Returns the resulting state,
-- or nil and the reason if some step is not allowed.
local function Simulate(steps)
	local state = SnapshotTalents()
	for i = 1, table.getn(steps) do
		local reason = CheckAdd(state, steps[i].tab, steps[i].index)
		if reason then
			return nil, reason
		end
		TakeRank(state, steps[i].tab, steps[i].index)
	end
	return state
end

local function PlannedRanks(tab, index)
	local n = 0
	for i = 1, table.getn(plan) do
		if plan[i].tab == tab and plan[i].index == index then
			n = n + 1
		end
	end
	return n
end

local function AddToPlan(tab, index, allRanks)
	local state = Simulate(plan)
	if not state then
		plan = {}
		state = SnapshotTalents()
	end
	local added = 0
	repeat
		local reason = CheckAdd(state, tab, index)
		if reason then
			if added == 0 then
				Error(reason)
			end
			return
		end
		TakeRank(state, tab, index)
		table.insert(plan, { tab = tab, index = index })
		added = added + 1
	until not allRanks
end

-- Removes the most recently planned rank of the talent. Refuses if other
-- planned talents depend on it (tier requirement or prerequisite).
local function RemoveOneRank(tab, index)
	for i = table.getn(plan), 1, -1 do
		if plan[i].tab == tab and plan[i].index == index then
			local step = table.remove(plan, i)
			if Simulate(plan) then
				return true
			end
			table.insert(plan, i, step)
			Error("Other planned talents depend on this one.")
			return false
		end
	end
	return false
end

local function RemoveFromPlan(tab, index, allRanks)
	while RemoveOneRank(tab, index) and allRanks do
	end
end

local function ClearPlan()
	plan = {}
	Refresh()
end

------------------------------------------------------------------------------
-- Learning
------------------------------------------------------------------------------

local function StopApplying()
	applying = false
	TP:Hide()
	Refresh()
end

-- Sends one rank at a time and waits until the server has accepted it, so the
-- tier and prerequisite order of the plan is preserved.
local function SendNext()
	local step = plan[1]
	if not step then
		Print("All planned talents have been learned.")
		StopApplying()
		return
	end
	local _, _, _, _, rank = GetTalentInfo(step.tab, step.index)
	applyTarget = rank + 1
	applyTimer = 0
	LearnTalent(step.tab, step.index)
end

local function StartLearning()
	if applying or table.getn(plan) == 0 then
		return
	end
	local state, reason = Simulate(plan)
	if not state then
		Error("Your plan is no longer valid: " .. reason)
		ClearPlan()
		return
	end
	applying = true
	TP:Show()
	Refresh()
	SendNext()
end

TP:Hide()
TP:SetScript("OnUpdate", function()
	local step = plan[1]
	if not applying or not step then
		return
	end
	applyTimer = applyTimer + arg1
	local name, _, _, _, rank = GetTalentInfo(step.tab, step.index)
	if rank >= applyTarget then
		table.remove(plan, 1)
		SendNext()
	elseif applyTimer > APPLY_TIMEOUT then
		Error("The server did not accept " .. name .. ". The rest of your plan was kept.")
		StopApplying()
	end
end)

local function PlanSummary()
	local lines, seen = {}, {}
	for i = 1, table.getn(plan) do
		local step = plan[i]
		local key = step.tab .. ":" .. step.index
		if not seen[key] then
			seen[key] = true
			local name, _, _, _, rank, maxRank = GetTalentInfo(step.tab, step.index)
			table.insert(lines, string.format("%s  %d/%d -> %d/%d",
				name, rank, maxRank, rank + PlannedRanks(step.tab, step.index), maxRank))
		end
	end
	return table.concat(lines, "\n")
end

StaticPopupDialogs["TALENTPLUS_CONFIRM"] = {
	text = "Learn %s talent point(s)?\n\n%s",
	button1 = "Learn",
	button2 = CANCEL,
	OnAccept = function()
		StartLearning()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

local function RequestLearn()
	if applying or table.getn(plan) == 0 then
		return
	end
	if TalentPlusDB.confirm then
		StaticPopup_Show("TALENTPLUS_CONFIRM", table.getn(plan), PlanSummary())
	else
		StartLearning()
	end
end

------------------------------------------------------------------------------
-- Talent frame integration
------------------------------------------------------------------------------

-- Runs after the default TalentFrame_Update and draws the plan on top of it.
local function Overlay()
	if table.getn(plan) == 0 then
		return
	end
	local state = Simulate(plan)
	if not state then
		return
	end
	local tab = PanelTemplates_GetSelectedTab(TalentFrame)
	local t = state.tabs[tab]
	if not t then
		return
	end
	for i = 1, MAX_TALENT_BUTTONS do
		local button = getglobal("TalentFrameTalent" .. i)
		if not button then
			break
		end
		local talent = t.talents[button:GetID()]
		if button:IsShown() and talent then
			local name = button:GetName()
			local rankText = getglobal(name .. "Rank")
			local rankBorder = getglobal(name .. "RankBorder")
			local slot = getglobal(name .. "Slot")
			if PlannedRanks(tab, button:GetID()) > 0 then
				if rankText then
					rankText:SetText(talent.rank)
					rankText:SetTextColor(PLAN_R, PLAN_G, PLAN_B)
					rankText:Show()
				end
				if rankBorder then
					rankBorder:Show()
				end
				if slot then
					slot:SetVertexColor(PLAN_R, PLAN_G, PLAN_B)
				end
				SetItemButtonDesaturated(button, nil)
			elseif talent.rank > 0 or not CheckAdd(state, tab, button:GetID()) then
				SetItemButtonDesaturated(button, nil)
			else
				SetItemButtonDesaturated(button, 1)
			end
		end
	end
end

local function UpdateControls()
	if not learnButton then
		return
	end
	local count = table.getn(plan)
	if applying then
		learnButton:SetText("Learning...")
	elseif count > 0 then
		learnButton:SetText("Learn (" .. count .. ")")
	else
		learnButton:SetText("Learn")
	end
	if count > 0 and not applying then
		learnButton:Enable()
		clearButton:Enable()
	else
		learnButton:Disable()
		clearButton:Disable()
	end
end

Refresh = function()
	if TalentFrame and TalentFrame:IsVisible() and TalentFrame_Update then
		TalentFrame_Update()
	end
	UpdateControls()
end

local function OnTalentClick()
	if applying then
		Error("Please wait, talents are being learned.")
		return
	end
	local tab = PanelTemplates_GetSelectedTab(TalentFrame)
	local index = this:GetID()
	if arg1 == "RightButton" then
		RemoveFromPlan(tab, index, IsShiftKeyDown())
	else
		AddToPlan(tab, index, IsShiftKeyDown())
	end
	Refresh()
	if GameTooltip:IsOwned(this) then
		local onEnter = this:GetScript("OnEnter")
		if onEnter then
			onEnter()
		end
	end
end

local function CreateControls()
	learnButton = CreateFrame("Button", "TalentPlusLearnButton", TalentFrame, "UIPanelButtonTemplate")
	learnButton:SetWidth(84)
	learnButton:SetHeight(22)
	if TalentFrameCancelButton then
		learnButton:SetPoint("RIGHT", TalentFrameCancelButton, "LEFT", -2, 0)
	else
		learnButton:SetPoint("BOTTOMRIGHT", TalentFrame, "BOTTOMRIGHT", -42, 80)
	end
	learnButton:SetScript("OnClick", RequestLearn)
	learnButton:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText("Learn planned talents")
		GameTooltip:AddLine("Left-click a talent to plan a rank, right-click to remove it.", 1, 1, 1, 1)
		GameTooltip:AddLine("Hold Shift to plan or remove all ranks at once.", 1, 1, 1, 1)
		GameTooltip:Show()
	end)
	learnButton:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	clearButton = CreateFrame("Button", "TalentPlusClearButton", TalentFrame, "UIPanelButtonTemplate")
	clearButton:SetWidth(60)
	clearButton:SetHeight(22)
	clearButton:SetPoint("RIGHT", learnButton, "LEFT", -2, 0)
	clearButton:SetText("Clear")
	clearButton:SetScript("OnClick", ClearPlan)
end

local function HookTalentFrame()
	if hooked or not TalentFrame or not TalentFrame_Update then
		return
	end
	hooked = true

	local origUpdate = TalentFrame_Update
	TalentFrame_Update = function()
		origUpdate()
		Overlay()
	end

	for i = 1, MAX_TALENT_BUTTONS do
		local button = getglobal("TalentFrameTalent" .. i)
		if not button then
			break
		end
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetScript("OnClick", OnTalentClick)
	end

	CreateControls()
	UpdateControls()
end

local origSetTalent = GameTooltip.SetTalent
GameTooltip.SetTalent = function(self, tab, index)
	origSetTalent(self, tab, index)
	local planned = PlannedRanks(tab, index)
	if planned > 0 then
		local _, _, _, _, rank, maxRank = GetTalentInfo(tab, index)
		self:AddLine(string.format("Planned: +%d (rank %d/%d after Learn)", planned, rank + planned, maxRank),
			PLAN_R, PLAN_G, PLAN_B)
		self:Show()
	end
end

------------------------------------------------------------------------------
-- Events and slash commands
------------------------------------------------------------------------------

TP:RegisterEvent("VARIABLES_LOADED")
TP:RegisterEvent("ADDON_LOADED")
TP:RegisterEvent("PLAYER_LOGIN")
TP:RegisterEvent("CHARACTER_POINTS_CHANGED")
TP:SetScript("OnEvent", function()
	if event == "VARIABLES_LOADED" then
		TalentPlusDB = TalentPlusDB or {}
		if TalentPlusDB.confirm == nil then
			TalentPlusDB.confirm = true
		end
	elseif event == "ADDON_LOADED" then
		if arg1 == "Blizzard_TalentUI" then
			HookTalentFrame()
		end
	elseif event == "PLAYER_LOGIN" then
		HookTalentFrame()
	elseif event == "CHARACTER_POINTS_CHANGED" then
		-- Talents changed outside of TalentPlus (reset, another addon...).
		if not applying and table.getn(plan) > 0 and not Simulate(plan) then
			Print("Your talents changed, so the plan was cleared.")
			ClearPlan()
		end
	end
end)

SLASH_TALENTPLUS1 = "/talentplus"
SLASH_TALENTPLUS2 = "/tplus"
SlashCmdList["TALENTPLUS"] = function(msg)
	msg = string.lower(msg or "")
	if msg == "confirm" then
		TalentPlusDB.confirm = not TalentPlusDB.confirm
		Print("Confirmation popup " .. (TalentPlusDB.confirm and "enabled." or "disabled."))
	elseif msg == "clear" then
		ClearPlan()
		Print("Plan cleared.")
	elseif msg == "learn" then
		RequestLearn()
	else
		Print("/tplus learn - learn the planned talents")
		Print("/tplus clear - clear the plan")
		Print("/tplus confirm - toggle the confirmation popup")
	end
end
