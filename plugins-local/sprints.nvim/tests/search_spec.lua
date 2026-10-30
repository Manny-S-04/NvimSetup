-- Finding items by number/words: per-sprint search (find.lua), order, concurrency, cache.
local client = require("sprints.api.client")
local find = require("sprints.api.find")
local sprints = require("sprints.api.sprints")
local workspace = require("sprints.api.workspace")

local function await(fn)
  local done, a, b, c = false, nil, nil, nil
  fn(function(x, y, z)
    done, a, b, c = true, x, y, z
  end)
  vim.wait(2000, function()
    return done
  end, 5)
  assert.is_true(done, "callback never ran")
  return a, b, c
end

-- A sprint item list in Zoho's positional shape (item_prop as seen on the real EU response).
-- rows: { id, itemNo, name, sprintId }
local function body(rows)
  local b = { itemIds = {}, itemJObj = {}, item_prop = { itemName = 0, itemNo = 1, sprintId = 32 } }
  for _, r in ipairs(rows) do
    table.insert(b.itemIds, r[1])
    local values = {} -- sparse, as client.lua decodes JSON nulls (luanil)
    values[1], values[2], values[33] = r[3], r[2], r[4]
    b.itemJObj[r[1]] = values
  end
  return b
end

describe("find.item_number", function()
  it("reduces any key form to the digits the API stores", function()
    assert.are.equal("22516", find.item_number("CV-I22516"))
    assert.are.equal("22516", find.item_number("cv-i22516"))
    assert.are.equal("22516", find.item_number("I22516"))
    assert.are.equal("22516", find.item_number("#22516"))
    assert.are.equal("22516", find.item_number(22516))
    assert.is_nil(find.item_number("hello"))
    assert.is_nil(find.item_number(nil))
  end)
end)

describe("find.order", function()
  local list = sprints.sort({
    { id = "c1", state = "completed", no = 1 }, { id = "a", state = "active", no = 5 },
    { id = "u", state = "upcoming", no = 6 }, { id = "c4", state = "completed", no = 4 },
    { id = "x", state = "cancelled", no = 3 },
  })

  it("puts the cached sprint first, then active, backlog, upcoming, completed newest first", function()
    assert.are.same({ "c1", "a", "B", "u", "c4", "x" }, find.order(list, "B", "c1", "all"))
    assert.are.same({ "a", "B", "u", "c4", "c1", "x" }, find.order(list, "B", nil, "all"))
  end)

  it("open scope skips completed and cancelled sprints", function()
    assert.are.same({ "a", "B", "u" }, find.order(list, "B", nil, "open"))
  end)

  it("copes with no backlog", function()
    assert.are.same({ "a", "u" }, find.order(list, nil, nil, "open"))
  end)
end)

describe("find.run", function()
  -- worker that answers asynchronously, tracking the most requests in flight at once
  local function worker(answers, stats)
    return function(id, done)
      stats.in_flight, stats.calls = stats.in_flight + 1, stats.calls + 1
      stats.max = math.max(stats.max, stats.in_flight)
      vim.defer_fn(function()
        stats.in_flight = stats.in_flight - 1
        local a = answers[id]
        if a == "err" then
          return done(nil, { message = "boom " .. id })
        end
        done(a, nil)
      end, 1)
    end
  end

  it("first: stops at a hit and never exceeds the concurrency limit", function()
    local ids, answers = {}, {}
    for i = 1, 40 do
      ids[i] = "s" .. i
    end
    answers.s15 = "found"
    local stats = { in_flight = 0, max = 0, calls = 0 }
    local value, errors = await(function(cb)
      find.run(ids, 6, "first", worker(answers, stats), cb)
    end)
    assert.are.equal("found", value)
    assert.are.equal(0, errors)
    assert.is_true(stats.max <= 6)
    assert.is_true(stats.calls < 40, "kept searching after the hit")
  end)

  it("first: failures don't stop the search, and are counted", function()
    local stats = { in_flight = 0, max = 0, calls = 0 }
    local value, errors, first = await(function(cb)
      find.run({ "a", "b", "c" }, 2, "first", worker({ a = "err", c = "hit" }, stats), cb)
    end)
    assert.are.equal("hit", value)
    assert.are.equal(1, errors)
    assert.are.equal("boom a", first.message)
  end)

  it("all: collects every hit in id order", function()
    local stats = { in_flight = 0, max = 0, calls = 0 }
    local out = await(function(cb)
      find.run({ "a", "b", "c", "d" }, 3, "all", worker({ a = 1, c = 3, d = 4 }, stats), cb)
    end)
    assert.are.same({ 1, 3, 4 }, out)
  end)

  it("handles no ids", function()
    local out = await(function(cb)
      find.run({}, 6, "all", function() end, cb)
    end)
    assert.are.same({}, out)
  end)
end)

describe("find.item / find.search", function()
  local orig = {}
  local requests, by_sprint

  before_each(function()
    orig.request, orig.list, orig.backlog, orig.meta = client.request, sprints.list, sprints.backlog_id, workspace.meta
    orig.cache_path = find.cache_path
    local tmp = vim.fn.tempname() .. "/item_sprints.json"
    find.cache_path = function()
      return tmp
    end
    find.cache_reset()
    requests, by_sprint = {}, {}
    sprints.list = function(_, _, cb)
      cb(sprints.sort({
        { id = "old", state = "completed", no = 1 }, { id = "act", state = "active", no = 3 },
        { id = "older", state = "completed", no = 0 },
      }), nil)
    end
    sprints.backlog_id = function(_, _, cb)
      cb("BL", nil)
    end
    workspace.meta = function(_, _, cb)
      cb({ statuses = {}, status_order = {}, users = {}, types = {}, priorities = {} }, nil)
    end
    client.request = function(method, path, opts, cb)
      local sprint = path:match("/sprints/([^/]+)/item/$")
      table.insert(requests, { method = method, path = path, query = opts.query, sprint = sprint })
      local r = by_sprint[sprint]
      if r == "err" then
        return cb(nil, { message = "7404 " .. sprint })
      end
      -- pages: a second page (index > 1) is empty, so paging stops
      if (opts.query.index or 1) > 1 then
        return cb({ status = 200, body = {} }, nil)
      end
      cb({ status = 200, body = r or {} }, nil)
    end
  end)

  after_each(function()
    client.request, sprints.list, sprints.backlog_id, workspace.meta =
      orig.request, orig.list, orig.backlog, orig.meta
    find.cache_path = orig.cache_path
    find.cache_reset()
  end)

  it("sends the confirmed sprint search query with digits only", function()
    by_sprint.act = body({ { "900", "22516", "Fix export", "act" } })
    local it_ = await(function(cb)
      find.item("T", "P", "CV-I22516", cb)
    end)
    assert.are.equal("900", it_.ref.item)
    assert.are.equal("act", it_.ref.sprint)
    assert.are.equal("Fix export", it_.summary)
    local q = requests[1].query
    assert.are.equal("/team/T/projects/P/sprints/act/item/", requests[1].path)
    assert.are.same({ "data", 1, "both", "22516", "true", 1, 25 },
      { q.action, q.viewtype, q.searchby, q.searchvalue, q.subitem, q.index, q.range })
  end)

  it("ignores near-misses (searchby=both also matches titles and longer numbers)", function()
    by_sprint.act = body({ { "901", "225160", "x", "act" }, { "902", "7", "about 22516", "act" } })
    by_sprint.old = body({ { "900", "22516", "the one", "old" } })
    local it_ = await(function(cb)
      find.item("T", "P", "22516", cb)
    end)
    assert.are.equal("900", it_.ref.item)
  end)

  it("remembers where it found an item and searches there first next time", function()
    by_sprint.older = body({ { "900", "22516", "x", "older" } })
    await(function(cb)
      find.item("T", "P", "22516", cb)
    end)
    assert.are.equal("older", find.cache_get("T", "P", "22516"))
    find.cache_reset() -- read back from disk
    requests = {}
    await(function(cb)
      find.item("T", "P", "22516", cb)
    end)
    assert.are.equal("older", requests[1].sprint)
  end)

  it("a stale cache entry just costs one request", function()
    find.cache_put("T", "P", "22516", "old") -- item has since moved to the active sprint
    by_sprint.act = body({ { "900", "22516", "x", "act" } })
    local it_ = await(function(cb)
      find.item("T", "P", "22516", cb)
    end)
    assert.are.equal("act", it_.ref.sprint)
    assert.are.equal("act", find.cache_get("T", "P", "22516"))
  end)

  it("reports not found, mentioning sprints whose search failed", function()
    by_sprint.old = "err"
    local it_, err = await(function(cb)
      find.item("T", "P", "22516", cb)
    end)
    assert.is_nil(it_)
    assert.matches("not found in 4 sprints", err.message)
    assert.matches("1 of 4 sprint searches failed", err.message)
  end)

  it("returns the real error when every sprint search fails", function()
    for _, s in ipairs({ "act", "BL", "old", "older" }) do
      by_sprint[s] = "err"
    end
    local it_, err = await(function(cb)
      find.item("T", "P", "22516", cb)
    end)
    assert.is_nil(it_)
    assert.matches("^7404", err.message)
  end)

  it("refuses keys without a number", function()
    local it_, err = await(function(cb)
      find.item("T", "P", "export", cb)
    end)
    assert.is_nil(it_)
    assert.matches("no item number", err.message)
    assert.are.equal(0, #requests)
  end)

  it("search: open scope skips completed sprints and drops duplicates", function()
    by_sprint.act = body({ { "900", "1", "export list", "act" } })
    by_sprint.BL = body({ { "900", "1", "export list", "act" }, { "901", "2", "export csv", "BL" } })
    by_sprint.old = body({ { "902", "3", "old export", "old" } })
    local hits = await(function(cb)
      find.search("T", "P", "export", "open", cb)
    end)
    assert.are.same({ "900", "901" }, vim.tbl_map(function(i) return i.id end, hits))
    for _, r in ipairs(requests) do
      assert.are_not.equal("old", r.sprint)
      assert.are.equal("export", r.query.searchvalue)
    end
  end)

  it("search: all scope includes completed sprints", function()
    by_sprint.old = body({ { "902", "3", "old export", "old" } })
    local hits = await(function(cb)
      find.search("T", "P", "export", "all", cb)
    end)
    assert.are.same({ "902" }, vim.tbl_map(function(i) return i.id end, hits))
  end)
end)
