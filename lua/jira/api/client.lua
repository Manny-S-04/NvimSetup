-- Low-level HTTP transport for the Jira REST API.
-- No knowledge of Neovim buffers/windows lives here.
local config = require("jira.config")
local auth = require("jira.api.auth")

local M = {}

--- Percent-encode a string for safe use in a URL.
function M.uri_encode(str)
  return (tostring(str):gsub("[^%w%-%.%_%~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

--- Build a full request URL from a base url, path, and optional query table.
--- Query keys are sorted for deterministic output (useful for tests).
function M.build_url(base_url, path, query)
  if not base_url or base_url == "" then
    error("jira.nvim: Jira URL is not configured")
  end

  local trimmed = base_url:gsub("/+$", "")
  if not path:match("^/") then
    path = "/" .. path
  end

  local url = trimmed .. path

  if query and next(query) ~= nil then
    local keys = {}
    for k in pairs(query) do
      table.insert(keys, k)
    end
    table.sort(keys)

    local parts = {}
    for _, k in ipairs(keys) do
      table.insert(parts, ("%s=%s"):format(M.uri_encode(k), M.uri_encode(tostring(query[k]))))
    end
    url = url .. "?" .. table.concat(parts, "&")
  end

  return url
end

local STATUS_MARKER = "\n__JIRA_NVIM_STATUS__"

local function parse_error_body(decoded, raw_body, status)
  if type(decoded) == "table" then
    if decoded.errorMessages and decoded.errorMessages[1] then
      return decoded.errorMessages[1]
    end
    if type(decoded.errors) == "table" then
      local parts = {}
      for field, msg in pairs(decoded.errors) do
        table.insert(parts, ("%s: %s"):format(field, msg))
      end
      if #parts > 0 then
        return table.concat(parts, "; ")
      end
    end
  end
  if raw_body and raw_body ~= "" then
    return raw_body
  end
  return "HTTP " .. tostring(status)
end

--- Perform a synchronous HTTP request against the configured Jira instance.
---@param method string e.g. "GET"
---@param path string e.g. "/rest/api/3/issue/PROJ-1"
---@param opts table|nil { query = table, body = table }
---@return table|nil result { status = number, body = table|nil }
---@return table|nil err { message = string, type = string, status = number|nil }
function M.request(method, path, opts)
  opts = opts or {}
  local cfg = config.options

  local ok_headers, headers_or_err = pcall(auth.headers, cfg)
  if not ok_headers then
    return nil, { message = tostring(headers_or_err), type = "auth" }
  end

  local ok_url, url = pcall(M.build_url, cfg.url, path, opts.query)
  if not ok_url then
    return nil, { message = tostring(url), type = "config" }
  end

  local cmd = { "curl", "-sS", "-X", method, url, "-w", STATUS_MARKER .. "%{http_code}" }

  for k, v in pairs(headers_or_err) do
    table.insert(cmd, "-H")
    table.insert(cmd, ("%s: %s"):format(k, v))
  end
  table.insert(cmd, "-H")
  table.insert(cmd, "Accept: application/json")

  if opts.body then
    table.insert(cmd, "-H")
    table.insert(cmd, "Content-Type: application/json")
    table.insert(cmd, "--data-raw")
    table.insert(cmd, vim.json.encode(opts.body))
  end

  table.insert(cmd, "--max-time")
  table.insert(cmd, tostring(math.max(1, math.floor((cfg.timeout or 10000) / 1000))))

  local sys_ok, sys_result = pcall(function()
    return vim.system(cmd, { text = true }):wait()
  end)

  if not sys_ok then
    return nil, {
      message = "jira.nvim: failed to invoke curl - is it installed and on $PATH? (" .. tostring(sys_result) .. ")",
      type = "transport",
    }
  end

  if sys_result.code ~= 0 then
    local stderr = sys_result.stderr and sys_result.stderr ~= "" and (": " .. sys_result.stderr) or ""
    return nil, {
      message = "jira.nvim: curl exited with code " .. tostring(sys_result.code) .. stderr,
      type = "transport",
    }
  end

  local stdout = sys_result.stdout or ""
  local body, status_str = stdout:match("^(.*)" .. STATUS_MARKER .. "(%d+)%s*$")
  if not body then
    return nil, { message = "jira.nvim: could not parse HTTP response from curl", type = "transport" }
  end

  local status = tonumber(status_str)
  local decoded = nil
  if body ~= "" then
    local decode_ok, decoded_or_err = pcall(vim.json.decode, body)
    if decode_ok then
      decoded = decoded_or_err
    end
  end

  if status < 200 or status >= 300 then
    return nil, {
      message = parse_error_body(decoded, body, status),
      status = status,
      type = "http",
      body = decoded,
    }
  end

  return { status = status, body = decoded }, nil
end

return M
