-- Everything cached about a project for the session: statuses / types / priorities / users
-- (workspace.meta), the item module and custom field definitions (fields). Zoho admins can
-- change any of these mid-session (e.g. a workflow edit replacing "To do"), and stale ids then
-- show as raw numbers or make updates fail, so this is what :SprintsReload and a failed
-- update clear. The auth token is deliberately not touched.
local M = {}

function M.clear()
  require("sprints.api.workspace").clear_cache()
  require("sprints.api.fields").clear_cache()
end

return M
