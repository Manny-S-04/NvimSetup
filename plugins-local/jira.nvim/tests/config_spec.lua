describe("jira.config", function()
  local config

  before_each(function()
    package.loaded["jira.config"] = nil
    config = require("jira.config")
  end)

  after_each(function()
    for _, var in ipairs({ "JIRA_URL", "JIRA_EMAIL", "JIRA_API_TOKEN" }) do
      vim.fn.setenv(var, vim.NIL)
    end
  end)

  it("uses explicit options when provided", function()
    local opts = config.setup({ url = "https://x.atlassian.net", email = "a@b.com", api_token = "tok" })
    assert.are.equal("https://x.atlassian.net", opts.url)
    assert.are.equal("a@b.com", opts.email)
    assert.are.equal("tok", opts.api_token)
  end)

  it("falls back to environment variables", function()
    vim.fn.setenv("JIRA_URL", "https://env.atlassian.net")
    vim.fn.setenv("JIRA_EMAIL", "env@example.com")
    vim.fn.setenv("JIRA_API_TOKEN", "env-token")

    local opts = config.setup({})
    assert.are.equal("https://env.atlassian.net", opts.url)
    assert.are.equal("env@example.com", opts.email)
    assert.are.equal("env-token", opts.api_token)
  end)

  it("prefers explicit options over environment variables", function()
    vim.fn.setenv("JIRA_EMAIL", "env@example.com")
    local opts = config.setup({ email = "explicit@example.com" })
    assert.are.equal("explicit@example.com", opts.email)
  end)

  it("reports incomplete configuration without erroring", function()
    local ok = config.setup({ url = "https://x.atlassian.net" })
    assert.is_false(config.is_configured())
    assert.is_not_nil(ok)
  end)
end)
