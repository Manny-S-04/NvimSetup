local ids = require("sprints.ids")

describe("sprints.ids", function()
  local known = { team = "T1", project = "P1", module = "M1", sprint = "S1", item = "42", key = "I12065" }

  it("fills every placeholder it has an id for", function()
    assert.are.equal("/team/T1/projects/P1/sprints/S1/item/42/",
      ids.fill("/team/{team}/projects/{project}/sprints/{sprint}/item/{item}/", known))
    assert.are.equal("/team/T1/settings/customization/modules/M1/fields/",
      ids.fill("/team/{team}/settings/customization/modules/{module}/fields/", known))
    assert.are.equal("/teams/", ids.fill("/teams/", {}))
  end)

  it("names the first placeholder it can't fill", function()
    local filled, missing = ids.fill("/team/{team}/projects/{project}/sprints/{sprint}/", { team = "T1", project = "P1" })
    assert.is_nil(filled)
    assert.are.equal("sprint", missing)
  end)

  it("reads ids off a ref, ignoring empty ones", function()
    assert.are.same({ team = "T1", project = "P1", sprint = nil, item = "42", key = "I1" },
      ids.from_ref({ team = "T1", project = 'P1', sprint = "", item = 42 }, "I1"))
    assert.are.same({}, ids.from_ref(nil, nil))
  end)

  it("lists the known ids in a fixed order with names alongside", function()
    local rows = ids.rows(vim.tbl_extend("force", known, { sprint_name = "Bug Clearing" }))
    assert.are.same({
      { label = "team (zsoid)", value = "T1" },
      { label = "project", value = "P1" },
      { label = "item module", value = "M1" },
      { label = "sprint (Bug Clearing)", value = "S1" },
      { label = "item (I12065)", value = "42" },
    }, rows)
    assert.are.same({ { label = "team (zsoid)", value = "T1" } }, ids.rows({ team = "T1" }))
  end)
end)

describe("sprints.api.cache", function()
  it("clears the project caches so the next call re-fetches", function()
    local fields = require("sprints.api.fields")
    local config = require("sprints.config")
    local client = require("sprints.api.client")
    local saved_req, saved_id = client.request, config.options.item_module_id
    config.options.item_module_id = nil
    local calls = 0
    client.request = function(_, _, _, cb)
      calls = calls + 1
      cb({ body = { custommodule_prop = { moduleName = 0 }, custommoduleJObj = { M9 = { "item" } } } })
    end
    fields.clear_cache()
    fields.item_module("T", function() end)
    fields.item_module("T", function() end)
    assert.are.equal(1, calls)
    require("sprints.api.cache").clear()
    fields.item_module("T", function() end)
    assert.are.equal(2, calls)
    client.request, config.options.item_module_id = saved_req, saved_id
  end)
end)
