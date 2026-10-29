local render = require("sprints.ui.render")

describe("sprints.ui.render", function()
  it("renders an item with metadata, html description and comments", function()
    local lines = render.render({
      key = "I7", summary = "Fix login", status = "In Progress", assignee = "Manny",
      updated = "1700000000000", description = "<div>Steps<br>1</div>",
      comments = { { author = "Sam", created = "2026-10-27T10:00:00", body = "<p>ok</p>" } },
    })
    assert.are.equal("# I7", lines[1])
    assert.are.equal("Fix login", lines[3])
    assert.truthy(vim.tbl_contains(lines, "Status:       In Progress"))
    assert.truthy(vim.tbl_contains(lines, "Updated:      2023-11-14"))
    assert.truthy(vim.tbl_contains(lines, "Steps"))
    assert.truthy(vim.tbl_contains(lines, "Sam — 2026-10-27"))
    assert.are.equal("ok", lines[#lines])
  end)

  it("says why comments are missing", function()
    local lines = render.render({ key = "I1", comments_error = "HTTP 404" })
    assert.are.equal("(comments unavailable: HTTP 404)", lines[#lines])
  end)

  it("aligns list rows and maps lines to items", function()
    local a = { key = "I1", status = "Done", summary = "a", status_category = "done" }
    local b = { key = "I10", status = "To do", summary = "b" }
    local lines, hls, by_line = render.render_list("Sprint 4", { a, b })
    assert.are.equal("I1   Done   a", lines[3])
    assert.are.equal("I10  To do  b", lines[4])
    assert.are.equal(b, by_line[4])
    assert.are.equal("sprintsStatusDone", hls[3].hl_group)
  end)
end)
