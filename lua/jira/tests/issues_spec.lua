describe("jira.api.issues.validate_key", function()
  local issues = require("jira.api.issues")

  it("accepts valid keys", function()
    assert.is_true((issues.validate_key("PROJ-123")))
    assert.is_true((issues.validate_key("A-1")))
  end)

  it("rejects invalid keys", function()
    assert.is_false((issues.validate_key("proj123")))
    assert.is_false((issues.validate_key("")))
    assert.is_false((issues.validate_key(nil)))
    assert.is_false((issues.validate_key("PROJ-")))
  end)
end)

describe("jira.api.issues.get", function()
  local issues
  local client

  before_each(function()
    package.loaded["jira.api.issues"] = nil
    package.loaded["jira.api.client"] = nil
    client = require("jira.api.client")
    issues = require("jira.api.issues")
  end)

  it("returns a structured issue on success", function()
    client.request = function(method, path)
      assert.are.equal("GET", method)
      assert.is_not_nil(path:find("PROJ%-123"))
      return {
        status = 200,
        body = {
          id = "10001",
          key = "PROJ-123",
          self = "https://example.atlassian.net/rest/api/3/issue/10001",
          fields = {
            summary = "Fix payment retry logic",
            status = { name = "In Progress" },
            assignee = { displayName = "Alice" },
            reporter = { displayName = "Bob" },
            priority = { name = "High" },
            issuetype = { name = "Story" },
            description = { type = "doc", version = 1, content = {} },
            comment = { comments = {} },
          },
        },
      }, nil
    end

    local issue, err = issues.get("PROJ-123")
    assert.is_nil(err)
    assert.are.equal("PROJ-123", issue.key)
    assert.are.equal("Fix payment retry logic", issue.summary)
    assert.are.equal("In Progress", issue.status)
    assert.are.equal("Alice", issue.assignee)
  end)

  it("rejects a bad key without calling the client", function()
    local called = false
    client.request = function()
      called = true
    end

    local issue, err = issues.get("not a key")
    assert.is_nil(issue)
    assert.are.equal("validation", err.type)
    assert.is_false(called)
  end)

  it("propagates client errors", function()
    client.request = function()
      return nil, { message = "boom", type = "http", status = 404 }
    end

    local issue, err = issues.get("PROJ-1")
    assert.is_nil(issue)
    assert.are.equal(404, err.status)
  end)
end)
