-- Item buffers are named by key (sprints://I22516), like jira.nvim's jira://CV-1, and reopen by
-- name: harpoon, :e and sessions make a buffer from the name and BufReadCmd fills it.
local function item(id)
  return {
    id = id,
    key = "I" .. id,
    no = id,
    summary = "Item " .. id,
    status = "To do",
    status_category = "new",
    owner_ids = {},
    comments = {},
    ref = { team = "T", project = "P", sprint = "S", item = id },
  }
end

describe("sprints item buffers", function()
  local ui, found_for, got_ref

  before_each(function()
    for name in pairs(package.loaded) do
      if name:match("^sprints") then
        package.loaded[name] = nil
      end
    end
    require("sprints").setup({ dc = "eu", client_id = "c", client_secret = "s", refresh_token = "r", team_id = "T", project_id = "P" })
    package.loaded["sprints.api.find"] = {
      item = function(team, project, wanted, cb)
        found_for = { team, project, wanted }
        cb(item("22516"), nil)
      end,
    }
    local items = require("sprints.api.items")
    items.get = function(ref, cb)
      got_ref = ref
      cb(item(ref.item), nil)
    end
    package.loaded["sprints.worklist"] = { update = function() end }
    ui = require("sprints.ui.item")
    vim.cmd("silent! %bwipeout!")
  end)

  it("knows which buffer names are items", function()
    assert.are.equal("I22516", ui.key_from_name("sprints://I22516"))
    assert.are.equal("CV-I22516", ui.key_from_name("sprints://CV-I22516"))
    assert.is_nil(ui.key_from_name("sprints://list/active/P"))
    assert.is_nil(ui.key_from_name("sprints://raw/I22516"))
    assert.is_nil(ui.key_from_name("sprints://P/22516/edit"))
    assert.is_nil(ui.key_from_name("/home/me/I22516"))
    assert.are.equal("I22516", ui.key_from_name("sprints:/I22516")) -- slashes collapsed by a path normaliser
  end)

  it("open names the buffer by key and reuses it", function()
    local a = ui.open(item("22516"))
    assert.are.equal("sprints://I22516", vim.api.nvim_buf_get_name(a))
    assert.are.equal(a, ui.open(item("22516")))
    assert.are.equal("22516", ui.item_of(a).ref.item)
  end)

  it("a buffer made from the name alone loads the item (harpoon after :bd, :e, sessions)", function()
    local bufnr = vim.fn.bufadd("sprints://I22516")
    vim.fn.bufload(bufnr)
    vim.wait(1000, function()
      return ui.item_of(bufnr) ~= nil
    end, 5)
    assert.are.same({ "T", "P", "I22516" }, found_for)
    assert.are.equal("22516", got_ref.item)
    assert.are.equal("sprints-item", vim.bo[bufnr].filetype)
    assert.are.equal("nofile", vim.bo[bufnr].buftype)
    assert.are.equal("# I22516", vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1])
    vim.api.nvim_set_current_buf(bufnr)
    assert.are.equal(1, vim.fn.maparg("s", "n", false, true).buffer)
  end)

  it(":edit on the name reopens the same item buffer", function()
    vim.cmd("edit sprints://I22516")
    local bufnr = vim.api.nvim_get_current_buf()
    vim.wait(1000, function()
      return ui.item_of(bufnr) ~= nil
    end, 5)
    assert.are.equal("I22516", ui.item_of(bufnr).key)
    vim.cmd("enew")
    vim.cmd("edit sprints://I22516")
    assert.are.equal(bufnr, vim.api.nvim_get_current_buf())
  end)

  it("a collapsed name (sprints:/I22516, as harpoon stores it) lands on the real buffer", function()
    local real = ui.open(item("22516"))
    local stray = vim.fn.bufadd("sprints:/I22516")
    vim.fn.bufload(stray)
    vim.api.nvim_set_current_buf(stray) -- what harpoon's select does next
    vim.wait(1000, function()
      return not vim.api.nvim_buf_is_valid(stray)
    end, 5)
    assert.is_false(vim.api.nvim_buf_is_valid(stray))
    assert.are.equal(real, vim.api.nvim_get_current_buf())
  end)

  it("a collapsed name with no buffer open yet loads the item under the real name", function()
    local stray = vim.fn.bufadd("sprints:/I22516")
    vim.fn.bufload(stray)
    vim.api.nvim_set_current_buf(stray)
    vim.wait(1000, function()
      local cur = vim.api.nvim_get_current_buf()
      return cur ~= stray and ui.item_of(cur) ~= nil
    end, 5)
    assert.are.equal("sprints://I22516", vim.api.nvim_buf_get_name(0))
    assert.are.equal("I22516", ui.item_of(0).key)
  end)

  it("other sprints:// buffers are left alone", function()
    found_for = nil
    local bufnr = vim.fn.bufadd("sprints://list/active/P")
    vim.fn.bufload(bufnr)
    vim.wait(50)
    assert.is_nil(found_for)
  end)
end)
