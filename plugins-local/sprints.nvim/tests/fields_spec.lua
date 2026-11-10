local fields = require("sprints.api.fields")
local render = require("sprints.ui.render")
local ui_fields = require("sprints.ui.fields")

describe("sprints.api.fields", function()
  it("finds the item module in the modules list", function()
    assert.are.equal("M1", fields.parse_item_module({
      custommodule_prop = { moduleName = 0, entityType = 1 },
      custommoduleJObj = { M0 = { "sprint", 2 }, M1 = { "item", 3 } },
    }))
    assert.is_nil(fields.parse_item_module({}))
  end)

  it("reads options from the shapes Zoho nests them in", function()
    local want = { { id = "1", title = "Yes" }, { id = "2", title = "No" } }
    assert.are.same(want, fields.options({ { "Group", { ["1"] = { "Yes", nil, true }, ["2"] = { "No" } } } }))
    assert.are.same(want, fields.options({ ["1"] = "Yes", ["2"] = "No" }))
    assert.are.same(want, fields.options({ g = { options = { ["1"] = { optionTitle = "Yes" }, ["2"] = { optionTitle = "No" } } } }))
    assert.are.same({}, fields.options(vim.NIL))
  end)

  -- Trimmed from a live definitions response (2026-11-10).
  local live = {
    customfield_prop = { fieldName = 0, fieldType = 3, udfName = 6, fieldOption = 7, fieldProperties = 11, optionGroups = 13 },
    optgroup_prop = { groupName = 0, options = 1 },
    options_prop = { optionTitle = 0, userId = 1 },
    customfieldIds = { "509", "859", "175" },
    customfieldJObj = {
      ["509"] = { "Requested By", "", false, 7, false, false, "UDF_PKL1", 0, 2, -1, "", {}, 0, {
        groupIds = { "g2", "g1" },
        groupJObj = {
          g1 = { "Internal", { optionIds = { "o3" }, optionJObj = { o3 = { "Support Team", "" } } } },
          g2 = { "Clients", { optionIds = { "o2", "o1" }, optionJObj = { o1 = { "Unknown", "" }, o2 = { "Barts", "" } } } },
        },
      } },
      ["859"] = { "AI Assisted", "", false, 15, false, false, "UDF_BOOLEAN1", 0, 2, -1, "", {}, 0, {
        groupIds = { "gd" },
        groupJObj = { gd = { "Default", { optionIds = { "y", "n" }, optionJObj = { y = { "Yes", "" }, n = { "No", "" } } } } },
      } },
      ["175"] = { "Assignee", "Select Owner", true, 10, false, false, "OWNER_ID", 0, 2, -1, "", {}, 1, vim.empty_dict() },
    },
  }

  it("reads the live grouped optionGroups shape in Zoho's order, not group names", function()
    local defs = fields.parse_definitions(live)
    assert.are.same({
      { id = "o2", title = "Barts" },
      { id = "o1", title = "Unknown" },
      { id = "o3", title = "Support Team" },
    }, defs["509"].options)
    assert.are.same({ { id = "y", title = "Yes" }, { id = "n", title = "No" } }, defs["859"].options)
    assert.are.same({}, defs["175"].options)
  end)

  it("shows option titles for live picklist values", function()
    local defs = fields.parse_definitions(live)
    assert.are.equal("Barts", fields.display(defs["509"], "o2"))
    assert.are.equal("Yes", fields.display(defs["859"], "y"))
    assert.is_nil(fields.display(defs["859"], ""))
  end)

  it("keeps only the layout's UDF fields, in layout order, with the mandatory flag", function()
    local defs = {
      a = { id = "a", name = "A", udf = "UDF_CHAR1", options = {} },
      b = { id = "b", name = "B", udf = "UDF_PKL1", options = {} },
      c = { id = "c", name = "Status", udf = "STATUS_ID", options = {} },
      d = { id = "d", name = "Not in layout", udf = "UDF_CHAR2", options = {} },
    }
    local layout = fields.parse_layout({
      customfield_prop = { sequence = 0, isMandatory = 3 },
      sectionVSfields = { s = { fieldJObj = { a = { 5, "", "", false }, b = { 1, "", "", true }, c = { 0, "", "", true } } } },
    })
    local list = fields.merge(defs, layout)
    assert.are.same({ "B", "A" }, vim.tbl_map(function(f) return f.name end, list))
    assert.is_true(list[1].mandatory)
    assert.is_false(list[2].mandatory)
  end)

  it("knows how to ask for each UDF family", function()
    local k = function(udf) return fields.kind({ udf = udf }) end
    assert.are.same(
      { "one", "one", "many", "many", "user", "bool", "date", "datetime", "number", "number", "text", "text" },
      { k("UDF_PKL1"), k("UDF_RADIO2"), k("UDF_MULTIPKL1"), k("UDF_CHKBOX3"), k("UDF_USERPKL4"), k("UDF_BOOLEAN1"),
        k("UDF_DATE1"), k("UDF_DATETIME1"), k("UDF_LONG1"), k("UDF_DOUBLE1"), k("UDF_CHAR1"), k("UDF_RTEXT1") })
  end)

  it("shows values and finds empty mandatory fields", function()
    local pkl = { name = "AI", udf = "UDF_BOOLEAN1", mandatory = true, options = { { id = "o1", title = "Yes" } } }
    local multi = { name = "Tags", udf = "UDF_MULTIPKL1", options = { { id = "x", title = "X" }, { id = "y", title = "Y" } } }
    local who = { name = "Reviewer", udf = "UDF_USERPKL1", options = {} }
    local list = { pkl, multi, who }
    local users = { u1 = { name = "Sam" } }
    local item = { raw = { UDF_BOOLEAN1 = "-1", UDF_MULTIPKL1 = { "x", "y" }, UDF_USERPKL1 = "u1" } }
    local v = fields.values(item, list, users)
    assert.is_nil(v[1].text)
    assert.are.equal("X, Y", v[2].text)
    assert.are.equal("Sam", v[3].text)
    assert.are.same({ pkl }, fields.missing(item, list))
    item.raw.UDF_BOOLEAN1 = "o1"
    assert.are.same({}, fields.missing(item, list))
  end)

  it("encodes values the way update takes them", function()
    assert.are.equal('["x","y"]', fields.encode({ udf = "UDF_MULTIPKL1" }, { "x", "y" }))
    assert.are.equal("o1", fields.encode({ udf = "UDF_PKL1" }, "o1"))
    assert.are.equal("2026-11-05T00:00:00+00:00", ui_fields.date_value("2026-11-05"))
    assert.are.equal("2026-11-05T09:30:00+00:00", ui_fields.date_value("2026-11-05 09:30", true))
  end)
end)

describe("render: custom fields and comments", function()
  local item = {
    key = "I1",
    custom_fields = {
      { field = { name = "AI Assisted", mandatory = true }, text = nil },
      { field = { name = "Notes" }, text = nil },
      { field = { name = "A very long field name" }, text = "v" },
    },
    comments = {
      { id = "n1", author = "Sam", created = "2026-11-05T10:00:00Z", body = "<p>one</p><p>two</p>" },
      { id = "n2", author = "Me", created = "2026-11-05T11:00:00Z", updated = "2026-11-05T12:00:00Z", body = "<p>three</p>" },
    },
  }

  it("shows every layout field, empty required ones flagged and other empty ones as a dash", function()
    local lines = render.render(item)
    assert.truthy(vim.tbl_contains(lines, "AI Assisted:  (empty, required)"))
    assert.truthy(vim.tbl_contains(lines, "Notes:        —"))
    assert.truthy(vim.tbl_contains(lines, "A very long field name: v"))
  end)

  it("maps cursor lines to comments", function()
    local lines, _, marks = render.render(item)
    local sam, me
    for i, l in ipairs(lines) do
      if l:match("^Sam ") then
        sam = i - 1
      elseif l:match("^Me ") then
        me = i - 1
      end
    end
    local c1 = marks.comments[1]
    assert.are.equal(sam, c1.first)
    for l = c1.first, c1.last do
      assert.are.equal(1, render.comment_at(marks, l))
    end
    assert.is_nil(render.comment_at(marks, c1.last + 1)) -- blank line between comments
    assert.are.equal(2, render.comment_at(marks, me))
    assert.truthy(lines[me + 1]:find("(edited)", 1, true))
    assert.is_nil(render.comment_at(marks, 0))
  end)
end)
