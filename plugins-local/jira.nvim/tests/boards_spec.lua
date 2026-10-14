describe("jira.api.boards", function()
  local boards, client, calls

  -- Fake Agile API: route -> response body. Records every request.
  local function fake(routes)
    calls = {}
    client.request = function(method, path, opts, cb)
      table.insert(calls, { method = method, path = path, query = (opts or {}).query or {} })
      for pattern, body in pairs(routes) do
        if path:match(pattern) then
          local b = type(body) == "function" and body(opts.query or {}) or body
          return cb({ status = 200, body = b }, nil)
        end
      end
      cb(nil, { message = "unexpected " .. path })
    end
  end

  local function issue(key)
    return { id = key, key = key, fields = { summary = "s " .. key, status = { name = "To Do" } } }
  end

  before_each(function()
    for _, m in ipairs({ "jira.api.boards", "jira.api.issues", "jira.api.client" }) do
      package.loaded[m] = nil
    end
    client = require("jira.api.client")
    boards = require("jira.api.boards")
  end)

  it("shows the active sprint of a scrum board, titled with the sprint", function()
    fake({
      ["/board/19$"] = { id = 19, name = "CV board", type = "scrum", location = { projectKey = "CV" } },
      ["/board/19/sprint$"] = { values = { { id = 7, name = "Sprint 42", endDate = "2026-10-20T12:00:00.000Z" } } },
      ["/board/19/issue$"] = { total = 2, issues = { issue("CV-1"), issue("CV-2") } },
    })
    local got, err, title
    boards.board_view("19", function(l, e, t) got, err, title = l, e, t end)
    assert.is_nil(err)
    assert.are.equal(2, #got)
    assert.are.equal("CV-1", got[1].key)
    assert.are.equal("CV board: Sprint 42 — ends 2026-10-20", title)
    assert.are.equal("active", calls[2].query.state)
    assert.are.equal("sprint in (7)", calls[3].query.jql)
    assert.is_truthy(calls[1].path:match("^/rest/agile/1%.0/board/19$"))
  end)

  it("uses open + recently done work for a kanban board", function()
    fake({
      ["/board/5$"] = { id = 5, name = "Ops", type = "kanban" },
      ["/board/5/issue$"] = { total = 1, issues = { issue("OPS-9") } },
    })
    local got, _, title
    boards.board_view("5", function(l, e, t) got, title = l, t end)
    assert.are.equal("OPS-9", got[1].key)
    assert.are.equal("Ops (board 5)", title)
    assert.are.equal(boards.kanban_jql, calls[2].query.jql)
  end)

  it("says so when a scrum board has no active sprint", function()
    fake({
      ["/board/3$"] = { id = 3, name = "B", type = "scrum" },
      ["/board/3/sprint$"] = { values = {} },
    })
    local got, _, title
    boards.board_view("3", function(l, e, t) got, title = l, t end)
    assert.are.equal(0, #got)
    assert.are.equal("B: no active sprint", title)
    assert.are.equal(2, #calls) -- no issue request
  end)

  it("follows pagination", function()
    fake({
      ["/board/1/issue$"] = function(q)
        local out = {}
        for i = q.startAt + 1, math.min(q.startAt + 50, 120) do
          table.insert(out, issue("P-" .. i))
        end
        return { total = 120, issues = out }
      end,
    })
    local got
    boards.issues("1", nil, function(l) got = l end)
    assert.are.equal(120, #got)
    assert.are.equal("P-120", got[120].key)
    assert.are.equal(3, #calls)
  end)

  it("propagates errors", function()
    fake({})
    local got, err
    boards.board_view("99", function(l, e) got, err = l, e end)
    assert.is_nil(got)
    assert.is_truthy(err.message:match("unexpected"))
  end)
end)
