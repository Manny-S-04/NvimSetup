describe("jira.config deployment detection", function()
  local config
  before_each(function()
    package.loaded["jira.config"] = nil
    config = require("jira.config")
  end)

  it("treats *.atlassian.net as Cloud (API v3)", function()
    config.setup({ url = "https://corp.atlassian.net", email = "a@b.com", api_token = "t" })
    assert.is_true(config.is_cloud())
    assert.are.equal("3", config.api_version())
  end)

  it("treats other hosts as Server/DC (API v2) and needs no email", function()
    config.setup({ url = "https://jira.corp.local", api_token = "pat" })
    assert.is_false(config.is_cloud())
    assert.are.equal("2", config.api_version())
    assert.is_true(config.is_configured())
  end)

  it("honours an explicit deployment override", function()
    config.setup({ url = "https://jira.corp.local", email = "a@b.com", api_token = "t", deployment = "cloud" })
    assert.is_true(config.is_cloud())
  end)

  it("requires an email for Cloud", function()
    config.setup({ url = "https://corp.atlassian.net", api_token = "t" })
    assert.is_false(config.is_configured())
  end)
end)

describe("jira.api.auth", function()
  local auth = require("jira.api.auth")

  it("uses Basic auth when an email is set", function()
    local h = auth.headers({ email = "a@b.com", api_token = "tok" })
    assert.are.equal("Basic " .. vim.base64.encode("a@b.com:tok"), h.Authorization)
  end)

  it("uses a Bearer PAT when there is no email", function()
    assert.are.equal("Bearer pat", auth.headers({ api_token = "pat" }).Authorization)
  end)

  it("errors without a token", function()
    assert.has_error(function()
      auth.headers({ email = "a@b.com" })
    end)
  end)
end)

describe("jira.api.client secrets", function()
  local client, config, original_system
  before_each(function()
    package.loaded["jira.api.client"] = nil
    package.loaded["jira.config"] = nil
    config = require("jira.config")
    config.setup({ url = "https://example.atlassian.net", email = "me@example.com", api_token = "s3cret" })
    client = require("jira.api.client")
    original_system = vim.system
  end)
  after_each(function()
    vim.system = original_system
  end)

  it("sends the auth header and body via stdin, never argv", function()
    local seen_cmd, seen_opts
    vim.system = function(cmd, opts)
      seen_cmd, seen_opts = cmd, opts
      return {
        wait = function()
          return { code = 0, stdout = "\n__JIRA_NVIM_STATUS__204", stderr = "" }
        end,
      }
    end
    local result = client.request("POST", "/rest/api/3/issue/A-1/comment", { body = { text = 'say "hi"' } })
    assert.are.equal(204, result.status)
    local argv = table.concat(seen_cmd, " ")
    assert.is_nil(argv:find("s3cret", 1, true))
    assert.is_nil(argv:find(vim.base64.encode("me@example.com:s3cret"), 1, true))
    assert.is_not_nil(seen_opts.stdin:find("Authorization: Basic", 1, true))
    assert.is_not_nil(seen_opts.stdin:find('data-raw = "{\\"text\\":\\"say \\\\\\"hi\\\\\\"\\"}"', 1, true))
  end)

  it("decodes JSON null as nil, not vim.NIL", function()
    vim.system = function()
      return {
        wait = function()
          return { code = 0, stdout = '{"fields":{"assignee":null}}\n__JIRA_NVIM_STATUS__200', stderr = "" }
        end,
      }
    end
    local result = client.request("GET", "/x")
    assert.is_nil(result.body.fields.assignee)
  end)

  it("adds a hint to 401 errors", function()
    vim.system = function()
      return {
        wait = function()
          return { code = 0, stdout = '{"errorMessages":["Unauthorized"]}\n__JIRA_NVIM_STATUS__401', stderr = "" }
        end,
      }
    end
    local _, err = client.request("GET", "/x")
    assert.is_not_nil(err.message:find("JIRA_API_TOKEN", 1, true))
  end)

  it("calls back asynchronously on the main loop", function()
    vim.system = function(_, _, on_exit)
      on_exit({ code = 0, stdout = '{"ok":true}\n__JIRA_NVIM_STATUS__200', stderr = "" })
      return {}
    end
    local got
    client.request("GET", "/x", {}, function(result)
      got = result
    end)
    assert.is_nil(got) -- not yet: delivered via vim.schedule
    vim.wait(1000, function()
      return got ~= nil
    end)
    assert.is_true(got.body.ok)
  end)
end)

describe("jira.api.issues", function()
  local issues, client, config
  before_each(function()
    package.loaded["jira.api.issues"] = nil
    package.loaded["jira.api.client"] = nil
    package.loaded["jira.config"] = nil
    config = require("jira.config")
    client = require("jira.api.client")
    issues = require("jira.api.issues")
  end)

  it("converts plain text to ADF paragraphs with hard breaks", function()
    local doc = issues.text_to_adf("one\ntwo\n\nthree")
    assert.are.equal(2, #doc.content)
    assert.are.same({
      { type = "text", text = "one" },
      { type = "hardBreak" },
      { type = "text", text = "two" },
    }, doc.content[1].content)
    assert.are.equal("three", doc.content[2].content[1].text)
  end)

  it("uses /search/jql on Cloud and /search on Server", function()
    local paths = {}
    client.request = function(_, path)
      table.insert(paths, path)
      return { status = 200, body = { issues = {} } }
    end
    config.setup({ url = "https://corp.atlassian.net", email = "a@b.com", api_token = "t" })
    issues.search("project = X")
    config.setup({ url = "https://jira.corp.local", api_token = "t" })
    issues.search("project = X")
    assert.are.same({ "/rest/api/3/search/jql", "/rest/api/2/search" }, paths)
  end)

  it("posts ADF comments on Cloud and plain text on Server", function()
    local bodies = {}
    client.request = function(_, _, opts)
      table.insert(bodies, opts.body.body)
      return { status = 201, body = {} }
    end
    config.setup({ url = "https://corp.atlassian.net", email = "a@b.com", api_token = "t" })
    issues.add_comment("A-1", "hello")
    config.setup({ url = "https://jira.corp.local", api_token = "t" })
    issues.add_comment("A-1", "hello")
    assert.are.equal("doc", bodies[1].type)
    assert.are.equal("hello", bodies[2])
  end)

  it("parses Server/DC sprint strings and prefers the active sprint", function()
    client.request = function()
      return {
        status = 200,
        body = {
          key = "A-1",
          fields = {
            customfield_10020 = {
              "com.atlassian.greenhopper.service.sprint.Sprint@1[id=1,state=CLOSED,name=Sprint 1,x=y]",
              "com.atlassian.greenhopper.service.sprint.Sprint@2[id=2,state=ACTIVE,name=Sprint 2,x=y]",
            },
          },
        },
      }
    end
    assert.are.equal("Sprint 2", issues.get("A-1").sprint)
  end)
end)

describe("jira.ui.render.render_list", function()
  local render = require("jira.ui.render")

  it("aligns columns and maps lines to keys", function()
    local lines, _, keys = render.render_list("Mine", {
      { key = "A-1", status = "To Do", summary = "first" },
      { key = "LONG-22", status = "In Progress", summary = "second" },
    })
    assert.are.equal("# Mine", lines[1])
    assert.are.equal("A-1      To Do        first", lines[3])
    assert.are.equal("LONG-22  In Progress  second", lines[4])
    assert.are.equal("A-1", keys[3])
    assert.are.equal("LONG-22", keys[4])
  end)
end)
