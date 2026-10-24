describe("jira.jql.build", function()
  local jql = require("jira.jql")

  it("defaults to just an ordering", function()
    assert.are.equal("ORDER BY updated DESC", jql.build({}))
  end)

  it("joins clauses in a stable order", function()
    assert.are.equal(
      'project = "PROJ" AND issuetype = "Bug" AND statusCategory != "Done" AND assignee = currentUser()'
        .. " AND sprint in openSprints() ORDER BY updated DESC",
      jql.build({ sprint = "open", assignee = "me", status = "open", issue_type = "Bug", project = "PROJ" })
    )
  end)

  it("quotes reserved-word project keys and type names with spaces", function()
    assert.are.equal('project = "IN" AND issuetype = "Sub-task" ORDER BY updated DESC',
      jql.build({ project = "IN", issue_type = "Sub-task" }))
  end)

  it("escapes quotes and backslashes in text", function()
    assert.are.equal('text ~ "say \\"hi\\" C:\\\\x" ORDER BY updated DESC', jql.build({ text = 'say "hi" C:\\x' }))
  end)

  it("ignores blank strings", function()
    assert.are.equal("ORDER BY updated DESC", jql.build({ project = " ", text = "", issue_type = "" }))
  end)

  it("handles unassigned, reporter, backlog and updated window", function()
    assert.are.equal(
      "assignee is EMPTY AND reporter = currentUser() AND sprint is EMPTY AND updated >= -7d ORDER BY updated DESC",
      jql.build({ assignee = "unassigned", reporter_me = true, sprint = "none", updated_within = "7d" })
    )
  end)
end)

describe("jira.jql.from_freeform", function()
  local jql = require("jira.jql")

  it("turns a bare key into a key lookup", function()
    assert.are.equal("key = PROJ-12", jql.from_freeform(" proj-12 "))
  end)

  it("turns plain words into a text search", function()
    assert.are.equal('text ~ "login timeout" ORDER BY updated DESC', jql.from_freeform("login timeout"))
  end)

  it("passes real JQL through untouched", function()
    for _, q in ipairs({ "project = X", "summary ~ foo", "status in (Done)", "ORDER BY created", "a != b" }) do
      assert.are.equal(q, jql.from_freeform(q))
    end
  end)
end)

describe("jira.api.meta parsers", function()
  local meta = require("jira.api.meta")

  it("parses Cloud paged and Server bare project lists", function()
    local want = { { key = "A", name = "Alpha" }, { key = "B", name = "B" } }
    assert.are.same(want, meta.parse_projects({ values = { { key = "B" }, { key = "A", name = "Alpha" } } }))
    assert.are.same(want, meta.parse_projects({ { key = "B" }, { key = "A", name = "Alpha" } }))
  end)

  it("dedupes and sorts issue type names", function()
    assert.are.same({ "Bug", "Task" }, meta.parse_issue_types({ { name = "Task" }, { name = "Bug" }, { name = "Task" } }))
  end)
end)
