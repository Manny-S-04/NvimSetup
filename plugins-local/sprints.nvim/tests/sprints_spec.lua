-- Sprint listing: one request per sprintType, state taken from the type queried.
local client = require("sprints.api.client")
local sprints = require("sprints.api.sprints")

local function await(fn)
  local done, a, b = false, nil, nil
  fn(function(x, y)
    done, a, b = true, x, y
  end)
  vim.wait(1000, function()
    return done
  end, 5)
  assert.is_true(done, "callback never ran")
  return a, b
end

-- A sprints page in Zoho's positional shape; rows are { id, name }.
local function page(rows)
  local body = { sprintIds = {}, sprintJObj = {}, sprint_prop = { sprintName = 0 } }
  for _, r in ipairs(rows) do
    table.insert(body.sprintIds, r[1])
    body.sprintJObj[r[1]] = { r[2] }
  end
  return body
end

describe("sprints.list", function()
  local original_request, requests

  before_each(function()
    original_request = client.request
    requests = {}
  end)

  after_each(function()
    client.request = original_request
  end)

  -- by_type: code -> rows (page 1 only; page 2 is empty). Unlisted codes return nothing.
  local function stub(by_type, fail)
    client.request = function(_, path, opts, cb)
      table.insert(requests, { path = path, query = opts.query })
      local code = opts.query.type and opts.query.type[1]
      vim.schedule(function()
        if fail and fail[code] then
          return cb(nil, { message = "bad type " .. code })
        end
        local rows = opts.query.index == 1 and by_type[code] or {}
        cb({ status = 200, body = page(rows or {}) })
      end)
    end
  end

  it("asks for each type and takes the state from the query", function()
    stub({ [2] = { { "a1", "export list" } }, [1] = { { "u1", "ready to test" } }, [3] = { { "c1", "old" } } })
    local list, err = await(function(cb) sprints.list("T", "P", cb) end)
    assert.is_nil(err)
    local types = {}
    for _, r in ipairs(requests) do
      assert.are.equal("/team/T/projects/P/sprints/", r.path)
      assert.are.equal("data", r.query.action)
      types[r.query.type[1]] = true
    end
    assert.are.same({ [1] = true, [2] = true, [3] = true, [4] = true }, types)
    assert.are.same({ "export list", "ready to test", "old" }, { list[1].name, list[2].name, list[3].name })
    assert.are.same({ "active", "upcoming", "completed" }, { list[1].state, list[2].state, list[3].state })
  end)

  it("active() returns the active sprint", function()
    stub({ [2] = { { "a1", "export list" } }, [1] = { { "u1", "ready to test" } } })
    local active = await(function(cb) sprints.active("T", "P", cb) end)
    assert.are.equal(1, #active)
    assert.are.equal("export list", active[1].name)
  end)

  it("falls back to the row's own state when the server ignores type", function()
    local same = { { "x1", "whatever" } }
    stub({ [1] = same, [2] = same, [3] = same, [4] = same })
    local list = await(function(cb) sprints.list("T", "P", cb) end)
    assert.are.equal(1, #list)
    assert.is_nil(list[1].state) -- no type field in the row: unknown, not wrongly "active"
  end)

  it("survives one type failing, errors only if all fail", function()
    stub({ [2] = { { "a1", "export list" } } }, { [4] = true })
    local list, err = await(function(cb) sprints.list("T", "P", cb) end)
    assert.is_nil(err)
    assert.are.equal("export list", list[1].name)

    stub({}, { [1] = true, [2] = true, [3] = true, [4] = true })
    local none, err2 = await(function(cb) sprints.list("T", "P", cb) end)
    assert.is_nil(none)
    assert.are.equal("bad type 2", err2.message)
  end)
end)
