-- Team-wide item search (orgitemlogs): request shape, hit decoding, key variants, find_item.
local client = require("sprints.api.client")
local items = require("sprints.api.items")
local commands = require("sprints.commands")

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

-- A search body in Zoho's positional shape; rows are { id, no, name, project, sprint }.
local function body(rows, prefix)
  prefix = prefix or "item"
  local b = {
    [prefix .. "Ids"] = {},
    [prefix .. "JObj"] = {},
    [prefix .. "_prop"] = { itemName = 0, itemNo = 1, projectId = 2, sprintId = 3 },
    projectJObj = { P1 = { "Some project" } }, -- side table: has no project/sprint ids
  }
  for _, r in ipairs(rows) do
    table.insert(b[prefix .. "Ids"], r[1])
    b[prefix .. "JObj"][r[1]] = { r[3], r[2], r[4], r[5] }
  end
  return b
end

describe("items.search_hits", function()
  it("turns rows into openable refs in any project/sprint", function()
    local hits = items.search_hits(body({ { "900", "CV-I22516", "Fix export", "P1", "S9" } }), "T")
    assert.are.equal(1, #hits)
    assert.are.same({ team = "T", project = "P1", sprint = "S9", item = "900" }, hits[1].ref)
    assert.are.equal("CV-I22516", hits[1].key)
    assert.are.equal("Fix export", hits[1].name)
  end)

  it("finds rows under an unknown prefix and skips side tables", function()
    local hits = items.search_hits(body({ { "900", "I7", "x", "P1", "S9" } }, "orgItem"), "T")
    assert.are.equal(1, #hits)
    assert.are.equal("900", hits[1].ref.item)
  end)

  it("drops rows without project or sprint ids, and copes with junk", function()
    local b = body({ { "900", "I7", "x", "P1", "S9" } })
    b.itemJObj["900"][4] = nil -- no sprint
    assert.are.same({}, items.search_hits(b, "T"))
    assert.are.same({}, items.search_hits(nil, "T"))
    assert.are.same({}, items.search_hits({ status = "success" }, "T"))
  end)
end)

describe("items.key_variants", function()
  it("tries the typed key, then without project prefix, then digits", function()
    assert.are.same({ "CV-I22516", "I22516", "22516" }, items.key_variants("cv-I22516"))
    assert.are.same({ "I12", "12" }, items.key_variants("I12"))
    assert.are.same({ "12" }, items.key_variants("#12"))
  end)
end)

describe("search requests", function()
  local original_request, requests

  before_each(function()
    original_request = client.request
    requests = {}
  end)
  after_each(function()
    client.request = original_request
  end)

  it("sends the orgitemlogs query and the REQSIZE header", function()
    client.request = function(method, path, opts, cb)
      table.insert(requests, { method = method, path = path, opts = opts })
      cb({ status = 200, body = {} }, nil)
    end
    await(function(cb)
      items.search_raw("T", "itemid", "CV-I1", cb)
    end)
    local r = requests[1]
    assert.are.equal("GET", r.method)
    assert.are.equal("/team/T/timesheet/", r.path)
    assert.are.equal("orgitemlogs", r.opts.query.action)
    assert.are.equal("itemid", r.opts.query.searchby)
    assert.are.equal("CV-I1", r.opts.query.searchvalue)
    assert.are.equal("large", r.opts.headers["X-ZA-REQSIZE"])
  end)

  it("find_item tries variants until a hit matches the wanted key", function()
    client.request = function(_, _, opts, cb)
      local v = opts.query.searchvalue
      table.insert(requests, v)
      if v == "I22516" then
        return cb({ status = 200, body = body({ { "900", "CV-I22516", "x", "P1", "S9" } }) }, nil)
      end
      cb({ status = 200, body = {} }, nil)
    end
    local hit, err = await(function(cb)
      commands.find_item("T", "CV-I22516", cb)
    end)
    assert.is_nil(err)
    assert.are.same({ "CV-I22516", "I22516" }, requests)
    assert.are.equal("900", hit.ref.item)
  end)

  it("find_item ignores hits for other items and reports a miss", function()
    client.request = function(_, _, _, cb)
      cb({ status = 200, body = body({ { "901", "CV-I22517", "x", "P1", "S9" } }) }, nil)
    end
    local hit, err = await(function(cb)
      commands.find_item("T", "CV-I22516", cb)
    end)
    assert.is_nil(hit)
    assert.is_nil(err)
  end)

  it("find_item stops at a request error so the caller can fall back", function()
    client.request = function(_, _, opts, cb)
      table.insert(requests, opts.query.searchvalue)
      cb(nil, { message = "404" })
    end
    local hit, err = await(function(cb)
      commands.find_item("T", "CV-I22516", cb)
    end)
    assert.is_nil(hit)
    assert.are.equal("404", err.message)
    assert.are.equal(1, #requests)
  end)
end)
