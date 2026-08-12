-- Facade for the API layer. UI code may require submodules directly
-- (e.g. require("jira.api.issues")); this module exists as a stable
-- place to expose future resources (sprints, boards, search) without
-- changing existing call sites.
local M = {}

M.issues = require("jira.api.issues")

return M
