local Strings = {}

---@enum Strings.StringCategories
Strings.StringCategories = {
    None = 0,
    ReasonWhyCantYield = 1,
    ReasonWhyCantOvertake = 2,
    StateExitReason = 3,
}

---@type table<Strings.StringCategories,any>
Strings.StringNames = {}
Strings.StringValues = {}
Strings.StringSaveFunctions = {}

return Strings