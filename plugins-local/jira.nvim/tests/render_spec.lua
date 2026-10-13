describe("jira.ui.render", function()
  local render = require("jira.ui.render")

  local issue = {
    key = "PROJ-123",
    summary = "Fix payment retry logic",
    status = "In Progress",
    assignee = "Alice",
    reporter = "Bob",
    priority = "High",
    issue_type = "Story",
    sprint = "Payments Sprint 24",
    description = {
      type = "doc",
      version = 1,
      content = {
        { type = "paragraph", content = { { type = "text", text = "The current payment retry implementation..." } } },
      },
    },
    comments = {
      { author = "Alice", created = "2026-08-10T10:00:00.000+0000", body = "This appears related to PROJ-119." },
      { author = "Bob", created = "2026-08-11T09:00:00.000+0000", body = "I've reproduced this locally." },
    },
  }

  it("includes the heading and summary", function()
    local lines = render.render(issue)
    assert.are.equal("# PROJ-123", lines[1])
    assert.are.equal("Fix payment retry logic", lines[3])
  end)

  it("renders metadata labels", function()
    local text = table.concat((render.render(issue)), "\n")
    assert.is_not_nil(text:find("Status:%s+In Progress"))
    assert.is_not_nil(text:find("Assignee:%s+Alice"))
    assert.is_not_nil(text:find("Sprint:%s+Payments Sprint 24"))
  end)

  it("renders description and comments sections", function()
    local text = table.concat((render.render(issue)), "\n")
    assert.is_not_nil(text:find("## Description"))
    assert.is_not_nil(text:find("The current payment retry implementation"))
    assert.is_not_nil(text:find("## Comments"))
    assert.is_not_nil(text:find("Alice — 2026%-08%-10"))
    assert.is_not_nil(text:find("Bob — 2026%-08%-11"))
  end)

  it("returns a highlight spec for the top heading", function()
    local _, highlights = render.render(issue)
    local found = false
    for _, h in ipairs(highlights) do
      if h.hl_group == "jiraHeading" and h.line == 0 then
        found = true
      end
    end
    assert.is_true(found)
  end)
end)
