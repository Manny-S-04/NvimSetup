describe("jira.api.client.build_url", function()
  local client = require("jira.api.client")

  it("builds a url without query params", function()
    assert.are.equal(
      "https://example.atlassian.net/rest/api/3/issue/PROJ-1",
      client.build_url("https://example.atlassian.net", "/rest/api/3/issue/PROJ-1")
    )
  end)

  it("strips a trailing slash from the base url", function()
    assert.are.equal(
      "https://example.atlassian.net/rest/api/3/issue/PROJ-1",
      client.build_url("https://example.atlassian.net/", "/rest/api/3/issue/PROJ-1")
    )
  end)

  it("adds a sorted, encoded query string", function()
    local url = client.build_url("https://example.atlassian.net", "/rest/api/3/issue/PROJ-1", {
      fields = "summary,status",
      expand = "renderedFields",
    })
    assert.are.equal(
      "https://example.atlassian.net/rest/api/3/issue/PROJ-1?expand=renderedFields&fields=summary%2Cstatus",
      url
    )
  end)

  it("errors when the base url is missing", function()
    assert.has_error(function()
      client.build_url(nil, "/rest/api/3/issue/PROJ-1")
    end)
  end)
end)

describe("jira.api.client.request", function()
  local client
  local config
  local original_system

  before_each(function()
    package.loaded["jira.api.client"] = nil
    package.loaded["jira.config"] = nil
    config = require("jira.config")
    config.setup({ url = "https://example.atlassian.net", email = "me@example.com", api_token = "tok" })
    client = require("jira.api.client")
    original_system = vim.system
  end)

  after_each(function()
    vim.system = original_system
  end)

  it("decodes a successful JSON response", function()
    vim.system = function()
      return {
        wait = function()
          return { code = 0, stdout = '{"key":"PROJ-1"}\n__JIRA_NVIM_STATUS__200', stderr = "" }
        end,
      }
    end

    local result, err = client.request("GET", "/rest/api/3/issue/PROJ-1")
    assert.is_nil(err)
    assert.are.equal(200, result.status)
    assert.are.equal("PROJ-1", result.body.key)
  end)

  it("returns a structured error for a non-2xx status", function()
    vim.system = function()
      return {
        wait = function()
          return {
            code = 0,
            stdout = '{"errorMessages":["Issue does not exist"]}\n__JIRA_NVIM_STATUS__404',
            stderr = "",
          }
        end,
      }
    end

    local result, err = client.request("GET", "/rest/api/3/issue/PROJ-1")
    assert.is_nil(result)
    assert.are.equal(404, err.status)
    assert.are.equal("Issue does not exist", err.message)
  end)

  it("returns a transport error when curl exits non-zero", function()
    vim.system = function()
      return {
        wait = function()
          return { code = 7, stdout = "", stderr = "Failed to connect" }
        end,
      }
    end

    local result, err = client.request("GET", "/rest/api/3/issue/PROJ-1")
    assert.is_nil(result)
    assert.are.equal("transport", err.type)
  end)
end)
