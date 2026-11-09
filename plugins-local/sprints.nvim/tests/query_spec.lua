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

local function item(id, extra)
  return vim.tbl_extend("force", {
    id = id,
    key = "I" .. id,
    summary = "Item " .. id,
    status_id = "s1",
    status_category = "new",
    owner_ids = {},
    type_id = "t1",
    priority_id = "p1",
  }, extra or {})
end

describe("sprints.api.query matching", function()
  local q = require("sprints.api.query")

  it("owner: me / unassigned / anyone", function()
    local mine, theirs, nobody = item("1", { owner_ids = { "me" } }), item("2", { owner_ids = { "x" } }), item("3")
    assert.is_true(q.matches(mine, { owner = "me" }, "me"))
    assert.is_false(q.matches(theirs, { owner = "me" }, "me"))
    assert.is_true(q.matches(nobody, { owner = "unassigned" }))
    assert.is_false(q.matches(mine, { owner = "unassigned" }))
    assert.is_true(q.matches(theirs, {}))
  end)

  it("status categories and an exact status", function()
    local todo, doing, done = item("1"), item("2", { status_category = "indeterminate", status_id = "s2" }),
      item("3", { status_category = "done", status_id = "s3" })
    assert.is_true(q.matches(todo, { status = "open" }))
    assert.is_true(q.matches(doing, { status = "open" }))
    assert.is_false(q.matches(done, { status = "open" }))
    assert.is_true(q.matches(doing, { status = "inprogress" }))
    assert.is_false(q.matches(todo, { status = "inprogress" }))
    assert.is_true(q.matches(todo, { status = "todo" }))
    assert.is_true(q.matches(done, { status = "done" }))
    assert.is_true(q.matches(doing, { status_id = "s2" }))
    assert.is_false(q.matches(todo, { status_id = "s2" }))
  end)

  it("type, priority, created by me", function()
    assert.is_false(q.matches(item("1"), { type_id = "t2" }))
    assert.is_true(q.matches(item("1"), { priority_id = "p1" }))
    assert.is_true(q.matches(item("1", { created_by_id = "me" }), { created_by_me = true }, "me"))
    assert.is_false(q.matches(item("1", { created_by_id = "x" }), { created_by_me = true }, "me"))
    assert.is_false(q.matches(item("1"), { created_by_me = true }, nil))
  end)

  it("text matches key or title, case-insensitively, unless the server already searched", function()
    local it = item("22516", { summary = "RDE patient report" })
    assert.is_true(q.matches(it, { text = "patient" }))
    assert.is_true(q.matches(it, { text = "i22516" }))
    assert.is_false(q.matches(it, { text = "billing" }))
    assert.is_true(q.matches(it, { text = "billing" }, nil, true))
  end)

  it("describes a spec with project names", function()
    local meta = { statuses = { s2 = { name = "Ready to test" } }, types = { t1 = { name = "Bug" } }, priorities = { p1 = { name = "High" } } }
    assert.are.equal("active sprint", q.describe({}))
    assert.are.equal('open sprints + backlog · mine · not done · Bug · High priority · "login"',
      q.describe({ scope = "open", owner = "me", status = "open", type_id = "t1", priority_id = "p1", text = "login" }, meta))
    assert.are.equal("backlog · status Ready to test · created by me", q.describe({ scope = "backlog", status_id = "s2", created_by_me = true }, meta))
  end)

  it("drops duplicates, keeping order", function()
    assert.are.same({ "1", "2" }, vim.tbl_map(function(i)
      return i.id
    end, q.dedupe({ item("1"), item("2"), item("1") })))
  end)
end)

describe("sprints.api.query.run", function()
  local q, sprints, items, find, workspace

  before_each(function()
    for _, m in ipairs({ "sprints.api.query", "sprints.api.sprints", "sprints.api.items", "sprints.api.find", "sprints.api.workspace" }) do
      package.loaded[m] = nil
    end
    sprints, items = require("sprints.api.sprints"), require("sprints.api.items")
    find, workspace = require("sprints.api.find"), require("sprints.api.workspace")
    q = require("sprints.api.query")
    workspace.me = function(_, _, cb)
      cb("me", nil)
    end
  end)

  it("active scope: lists every active sprint and filters client-side", function()
    sprints.active = function(_, _, cb)
      cb({ { id = "S1" }, { id = "S2" } }, nil)
    end
    local listed = {}
    items.list = function(ref, cb)
      table.insert(listed, ref.sprint)
      cb(ref.sprint == "S1" and { item("1", { owner_ids = { "me" } }), item("2") } or { item("3", { owner_ids = { "me" } }) }, nil)
    end
    local found = await(function(cb)
      q.run("T", "P", { owner = "me" }, cb)
    end)
    table.sort(listed)
    assert.are.same({ "S1", "S2" }, listed)
    assert.are.same({ "I1", "I3" }, vim.tbl_map(function(i)
      return i.key
    end, found))
  end)

  it("text over open sprints goes to Zoho's search, item keys as their number", function()
    local searched
    find.search = function(_, _, value, scope, cb)
      searched = { value, scope }
      cb({ item("22516", { summary = "nothing like the text" }) }, nil)
    end
    items.list = function()
      error("no listing expected")
    end
    local found = await(function(cb)
      q.run("T", "P", { scope = "open", text = "CV-I22516" }, cb)
    end)
    assert.are.same({ "22516", "open" }, searched)
    assert.are.equal(1, #found) -- not re-filtered by text: the server matched it
  end)

  it("no active sprint is an error, not an empty list", function()
    sprints.active = function(_, _, cb)
      cb({}, nil)
    end
    local found, err = await(function(cb)
      q.run("T", "P", {}, cb)
    end)
    assert.is_nil(found)
    assert.truthy(err.message:find("no active sprint", 1, true))
  end)

  it("only asks who you are when the spec needs it", function()
    workspace.me = function()
      error("me not needed")
    end
    sprints.backlog_id = function(_, _, cb)
      cb("B", nil)
    end
    items.list = function(_, cb)
      cb({ item("1") }, nil)
    end
    local found = await(function(cb)
      q.run("T", "P", { scope = "backlog", status = "open" }, cb)
    end)
    assert.are.equal(1, #found)
  end)
end)
