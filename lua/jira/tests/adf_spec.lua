describe("jira.adf.to_lines", function()
  local adf = require("jira.adf")

  it("returns empty for nil", function()
    assert.are.same({}, adf.to_lines(nil))
  end)

  it("passes through plain strings", function()
    assert.are.same({ "hello", "world" }, adf.to_lines("hello\nworld"))
  end)

  it("renders a simple paragraph", function()
    local doc = {
      type = "doc",
      version = 1,
      content = { { type = "paragraph", content = { { type = "text", text = "Hello world" } } } },
    }
    assert.are.same({ "Hello world" }, adf.to_lines(doc))
  end)

  it("renders headings and bullet lists", function()
    local doc = {
      type = "doc",
      version = 1,
      content = {
        { type = "heading", attrs = { level = 2 }, content = { { type = "text", text = "Steps" } } },
        {
          type = "bulletList",
          content = {
            { type = "listItem", content = { { type = "paragraph", content = { { type = "text", text = "one" } } } } },
            { type = "listItem", content = { { type = "paragraph", content = { { type = "text", text = "two" } } } } },
          },
        },
      },
    }
    assert.are.same({ "## Steps", "", "- one", "- two" }, adf.to_lines(doc))
  end)

  it("applies bold/em/code marks", function()
    local doc = {
      type = "doc",
      version = 1,
      content = {
        {
          type = "paragraph",
          content = {
            { type = "text", text = "bold", marks = { { type = "strong" } } },
            { type = "text", text = " and " },
            { type = "text", text = "code", marks = { { type = "code" } } },
          },
        },
      },
    }
    assert.are.same({ "**bold** and `code`" }, adf.to_lines(doc))
  end)

  it("degrades gracefully for unsupported node types", function()
    local doc = {
      type = "doc",
      version = 1,
      content = { { type = "mediaSingle", content = { { type = "text", text = "fallback text" } } } },
    }
    assert.are.same({ "fallback text" }, adf.to_lines(doc))
  end)
end)
