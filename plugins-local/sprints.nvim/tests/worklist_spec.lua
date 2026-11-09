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

local REF = { team = "T", project = "P", sprint = "S" }

local function item(id, extra)
  return vim.tbl_extend("force", {
    id = id,
    key = "I" .. id,
    summary = "Item " .. id,
    status = "To do",
    status_category = "new",
    owner_ids = {},
    ref = vim.tbl_extend("force", REF, { item = id }),
  }, extra or {})
end

describe("sprints.worklist formatting", function()
  local wl = require("sprints.worklist")

  it("puts the key first so menu lines parse back", function()
    local line = wl.format_item({ value = "I12", context = { status = "In Progress", summary = "Fix retry" } })
    assert.are.equal("I12  [In Progress] Fix retry", line)
    assert.are.equal("I12", wl.parse_line(line))
  end)

  it("marks done items", function()
    local line = wl.format_item({ value = "I3", context = { status = "Done", status_category = "done", summary = "x" } })
    assert.are.equal("I3  ✓ [Done] x", line)
    assert.are.equal("I3", wl.parse_line(line))
  end)

  it("handles entries without context and bad lines", function()
    assert.are.equal("I9", wl.format_item({ value = "I9" }))
    assert.are.equal("I9", wl.parse_line("  i9  "))
    assert.are.equal("CV-I22516", wl.parse_line("cv-i22516  [Done] x"))
    assert.is_nil(wl.parse_line("not a key"))
    assert.is_nil(wl.parse_line(nil))
  end)

  it("keeps the ref, so an entry opens without a search", function()
    local e = wl.item_for(item("7"))
    assert.are.equal("I7", e.value)
    assert.are.same({ team = "T", project = "P", sprint = "S", item = "7" }, e.context.ref)
  end)

  it("refreshes with one list per sprint, and names entries it can't refresh", function()
    local refs, missing = wl.sprints_of({
      wl.item_for(item("1")),
      wl.item_for(item("2")),
      wl.item_for(item("3", { ref = { team = "T", project = "P", sprint = "B", item = "3" } })),
      { value = "I4", context = {} }, -- typed into the menu by hand
    })
    assert.are.same({ { team = "T", project = "P", sprint = "S" }, { team = "T", project = "P", sprint = "B" } }, refs)
    assert.are.same({ "I4" }, missing)
  end)
end)

describe("sprints.api.hierarchy", function()
  local hierarchy, items, sprints

  before_each(function()
    for _, m in ipairs({ "sprints.api.hierarchy", "sprints.api.items", "sprints.api.sprints" }) do
      package.loaded[m] = nil
    end
    items = require("sprints.api.items")
    sprints = require("sprints.api.sprints")
    hierarchy = require("sprints.api.hierarchy")
  end)

  it("treats Zoho's empty ids as no parent", function()
    for _, v in ipairs({ "", "0", "-1", -1, vim.NIL }) do
      assert.is_nil(items.real_id(v), vim.inspect(v))
    end
    assert.are.equal("46699000000223678", items.real_id("46699000000223678"))
  end)

  it("reads parentItem / isParent from a row", function()
    local it = items.normalise({ id = "9", itemNo = "9", parentItem = "5", isParent = "false" }, REF)
    assert.are.equal("5", it.parent_id)
    assert.is_false(it.is_parent)
    assert.is_nil(items.normalise({ id = "5", parentItem = "-1", isParent = "true" }, REF).parent_id)
    assert.is_true(items.normalise({ id = "5", isParent = true }, REF).is_parent)
  end)

  it("no parent: answers nil without a request", function()
    items.get = function()
      error("no request expected")
    end
    local p, err = await(function(cb)
      hierarchy.parent(item("1"), cb)
    end)
    assert.is_nil(p)
    assert.is_nil(err)
  end)

  it("fetches the parent in the child's sprint, then the backlog", function()
    local tried = {}
    items.get = function(ref, cb)
      table.insert(tried, ref.sprint .. "/" .. ref.item)
      if ref.sprint == "B" then
        return cb(item("5", { ref = ref }), nil)
      end
      cb(nil, { message = "not in this sprint" })
    end
    sprints.backlog_id = function(_, _, cb)
      cb("B", nil)
    end
    local p = await(function(cb)
      hierarchy.parent(item("9", { parent_id = "5" }), cb)
    end)
    assert.are.same({ "S/5", "B/5" }, tried)
    assert.are.equal("I5", p.key)
  end)

  it("reports the first error when the parent isn't found anywhere", function()
    items.get = function(_, cb)
      cb(nil, { message = "gone" })
    end
    sprints.backlog_id = function(_, _, cb)
      cb("B", nil)
    end
    local p, err = await(function(cb)
      hierarchy.parent(item("9", { parent_id = "5" }), cb)
    end)
    assert.is_nil(p)
    assert.are.equal("gone", err.message)
  end)

  it("children are the sprint's rows whose parent is the item, in list order", function()
    items.list = function(ref, cb)
      assert.are.same(REF, ref)
      cb({ item("2", { parent_id = "1" }), item("3"), item("4", { parent_id = "1" }), item("5", { parent_id = "9" }) }, nil)
    end
    local kids = await(function(cb)
      hierarchy.children(item("1"), cb)
    end)
    assert.are.same({ "I2", "I4" }, vim.tbl_map(function(k)
      return k.key
    end, kids))
  end)
end)

-- The real Harpoon (harpoon2), when it's on disk: the worklist must work with its API, not a fake.
local harpoon_dir = os.getenv("HARPOON_DIR") or "/tmp/harpoon"
local has_harpoon = vim.fn.isdirectory(harpoon_dir) == 1

describe("sprints.worklist with harpoon", function()
  if not has_harpoon then
    it("(skipped: set HARPOON_DIR to a harpoon2 checkout)", function() end)
    return
  end

  local wl, opened

  before_each(function()
    vim.opt.rtp:append(harpoon_dir)
    vim.fn.mkdir(vim.fn.stdpath("data") .. "/harpoon", "p") -- harpoon only makes the last level
    for name in pairs(package.loaded) do
      if name:match("^harpoon") or name == "sprints.worklist" or name == "sprints.ui.item" then
        package.loaded[name] = nil
      end
    end
    local key = vim.fn.tempname() -- a fresh harpoon key per test: no state from earlier runs
    require("harpoon"):setup({ settings = { key = function()
      return key
    end } })
    opened = {}
    package.loaded["sprints.ui.item"] = {
      open_ref = function(ref, key, opts)
        table.insert(opened, { ref = ref, key = key, opts = opts })
      end,
      item_of = function()
        return nil
      end,
    }
    wl = require("sprints.worklist")
    wl.open = function() end -- no quick menu in a headless test
  end)

  it("set fills the list; select opens by ref in the same window", function()
    wl.set({ item("1"), item("2") }, "I0 Parent")
    local list = wl.list()
    assert.are.equal(2, list:length())
    assert.are.equal("I1  [To do] Item 1", list.config.display(list.items[1]))
    list:select(2)
    assert.are.equal(1, #opened)
    assert.are.equal("I2", opened[1].key)
    assert.are.equal("2", opened[1].ref.item)
    assert.is_true(opened[1].opts.reuse_window)
  end)

  it("update keeps an entry's status current; others are untouched", function()
    wl.set({ item("1"), item("2") })
    assert.is_true(wl.update(item("2", { status = "Done", status_category = "done" })))
    assert.is_false(wl.update(item("99")))
    local list = wl.list()
    assert.is_true(wl.is_done(list.items[2].context))
    assert.is_false(wl.is_done(list.items[1].context))
  end)

  it("add appends one item without duplicating it", function()
    wl.set({ item("1") })
    wl.add(item("2"))
    wl.add(item("2"))
    assert.are.equal(2, wl.list():length())
  end)
end)
