local Strings = {}

---@enum Strings.StringCategories
Strings.StringCategories = {
    None = 0,
    ReasonWhyCantYield = 1,
    ReasonWhyCantOvertake = 2,
    StateExitReason = 3,
}

-- ---@type table<Strings.StringCategories,table<integer,integer>>
-- ---@type table<Strings.StringCategories,table<integer,Strings.ReasonWhyCantYield>>
-- ---@type table<Strings.StringCategories,table<integer,any>>
-- Andreas: I can't figure out the correct annotation for this
---@type table<Strings.StringCategories,any>
Strings.StringNames = {}
---@type table<Strings.StringCategories,table<integer,string>>
Strings.StringValues = {}
---@type table<Strings.StringCategories,function>
Strings.StringSaveFunctions = {}

return Strings