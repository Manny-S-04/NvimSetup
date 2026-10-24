describe("jira.worklist formatting", function()
  local wl = require("jira.worklist")

  it("puts the key first so menu lines parse back", function()
    local line = wl.format_item({ value = "CV-12", context = { status = "In Progress", summary = "Fix retry" } })
    assert.are.equal("CV-12  [In Progress] Fix retry", line)
    assert.are.equal("CV-12", wl.parse_line(line))
  end)

  it("marks done tickets", function()
    local line = wl.format_item({ value = "CV-3", context = { status = "Done", status_category = "done", summary = "x" } })
    assert.are.equal("CV-3  ✓ [Done] x", line)
    assert.are.equal("CV-3", wl.parse_line(line))
  end)

  it("handles items without context and bad lines", function()
    assert.are.equal("CV-9", wl.format_item({ value = "CV-9" }))
    assert.are.equal("CV-9", wl.parse_line("  cv-9  "))
    assert.is_nil(wl.parse_line("not a key"))
    assert.is_nil(wl.parse_line(nil))
  end)
end)

describe("jira.api.hierarchy", function()
  local hierarchy

  before_each(function()
    package.loaded["jira.api.hierarchy"] = nil
    package.loaded["jira.api.issues"] = nil
    package.loaded["jira.config"] = nil
    require("jira.config").setup({ url = "https://corp.atlassian.net", email = "a@b.com", api_token = "t" })
    hierarchy = require("jira.api.hierarchy")
  end)

  it("reads the parent field (Cloud shape)", function()
    local p = hierarchy.parent_from_fields({
      parent = { key = "CV-1", fields = { summary = "Epic", status = { name = "To Do" }, issuetype = { name = "Epic" } } },
    })
    assert.are.same({ key = "CV-1", summary = "Epic", status = "To Do", issue_type = "Epic" }, p)
  end)

  it("falls back to an Epic Link field on Server/DC", function()
    assert.are.same({ key = "CV-7" }, hierarchy.parent_from_fields({ customfield_10014 = "CV-7" }, "customfield_10014"))
    assert.is_nil(hierarchy.parent_from_fields({}, "customfield_10014"))
    assert.is_nil(hierarchy.parent_from_fields(nil))
  end)

  it("builds child JQL in board order with fallbacks", function()
    assert.are.same({ "parent = CV-1 ORDER BY Rank ASC", "parent = CV-1 ORDER BY key ASC" },
      hierarchy.children_jql("CV-1", { cloud = true }))
    local dc = hierarchy.children_jql("CV-1", { cloud = false, epic_link = true })
    assert.are.equal('(parent = CV-1 OR "Epic Link" = CV-1) ORDER BY Rank ASC', dc[1])
    assert.are.equal("parent = CV-1 ORDER BY key ASC", dc[#dc])
  end)

  it("retries the next query only when Jira rejects one (HTTP 400)", function()
    local issues = require("jira.api.issues")
    local seen = {}
    issues.search = function(jql, cb)
      table.insert(seen, jql)
      if #seen == 1 then return cb(nil, { status = 400, message = "Field 'Rank' does not exist" }) end
      cb({ { key = "CV-2" } }, nil)
    end
    local got
    hierarchy.children("CV-1", function(list) got = list end)
    assert.are.equal(2, #seen)
    assert.are.same({ { key = "CV-2" } }, got)
  end)

  it("does not retry auth / network errors", function()
    local issues = require("jira.api.issues")
    local calls = 0
    issues.search = function(_, cb) calls = calls + 1; cb(nil, { status = 401, message = "nope" }) end
    local err
    hierarchy.children("CV-1", function(_, e) err = e end)
    assert.are.equal(1, calls)
    assert.are.equal(401, err.status)
  end)
end)
