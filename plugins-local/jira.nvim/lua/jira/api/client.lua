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

--- Quote a value for a curl config file ("--config"): backslash-escape \ and ".
local function curl_quote(s)
  s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
  return '"' .. s .. '"'
end

local STATUS_MARKER = "\n__JIRA_NVIM_STATUS__"

local function parse_error_body(decoded, raw_body, status)
  local msg = nil
  if type(decoded) == "table" then
    if decoded.errorMessages and decoded.errorMessages[1] then
      msg = decoded.errorMessages[1]
    elseif type(decoded.errors) == "table" then
      local parts = {}
      for field, m in pairs(decoded.errors) do
        table.insert(parts, ("%s: %s"):format(field, m))
      end
      if #parts > 0 then
        msg = table.concat(parts, "; ")
      end
    end
  end
  if not msg and raw_body and raw_body ~= "" and #raw_body < 300 then
    msg = raw_body
  end
  msg = msg or ("HTTP " .. tostring(status))
  if status == 401 then
    msg = msg .. " (HTTP 401: check JIRA_EMAIL/JIRA_API_TOKEN, and that your organisation allows API tokens)"
  end
  return msg
end

--- Build the curl argv plus the stdin payload.
--- Secrets (the Authorization header) and the request body go through stdin as a curl
--- config file, never as argv, so they don't show up in process listings.
local function build_command(method, path, opts)
  local cfg = config.options

  local ok_headers, headers_or_err = pcall(auth.headers, cfg)
  if not ok_headers then
    return nil, nil, { message = tostring(headers_or_err), type = "auth" }
  end

  local ok_url, url = pcall(M.build_url, cfg.url, path, opts.query)
  if not ok_url then
    return nil, nil, { message = tostring(url), type = "config" }
  end

  local cmd = {
    "curl",
    "-sS",
    "-X",
    method,
    "--max-time",
    tostring(math.max(1, math.floor((cfg.timeout or 10000) / 1000))),
    "-w",
    STATUS_MARKER .. "%{http_code}",
    "--config",
    "-",
    url,
  }

  local stdin = {}
  local function header(k, v)
    table.insert(stdin, "header = " .. curl_quote(("%s: %s"):format(k, v)))
  end
  for k, v in pairs(headers_or_err) do
    header(k, v)
  end
  header("Accept", "application/json")
  if opts.body then
    header("Content-Type", "application/json")
    table.insert(stdin, "data-raw = " .. curl_quote(vim.json.encode(opts.body)))
  end

  return cmd, table.concat(stdin, "\n") .. "\n", nil
end

--- Turn a finished vim.system result into (result, err).
local function parse_result(sys_result)
  if sys_result.code ~= 0 then
    local stderr = sys_result.stderr and sys_result.stderr ~= "" and (": " .. vim.trim(sys_result.stderr)) or ""
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
    local decode_ok, decoded_or_err = pcall(vim.json.decode, body, { luanil = { object = true, array = true } })
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

--- Perform an HTTP request against the configured Jira instance.
--- With `callback` the request is asynchronous and the callback runs on the main loop as
--- callback(result, err). Without it the call blocks and returns (result, err).
---@param method string e.g. "GET"
---@param path string e.g. "/rest/api/3/issue/PROJ-1"
---@param opts table|nil { query = table, body = table }
---@param callback fun(result: table|nil, err: table|nil)|nil
---@return table|nil result { status = number, body = table|nil }
---@return table|nil err { message = string, type = string, status = number|nil }
function M.request(method, path, opts, callback)
  opts = opts or {}

  local cmd, stdin, build_err = build_command(method, path, opts)
  if not cmd then
    if callback then
      vim.schedule(function()
        callback(nil, build_err)
      end)
      return
    end
    return nil, build_err
  end

  local sys_opts = { text = true, stdin = stdin }

  if callback then
    local ok, err = pcall(vim.system, cmd, sys_opts, function(sys_result)
      local result, req_err = parse_result(sys_result)
      vim.schedule(function()
        callback(result, req_err)
      end)
    end)
    if not ok then
      vim.schedule(function()
        callback(nil, {
          message = "jira.nvim: failed to invoke curl - is it installed and on $PATH? (" .. tostring(err) .. ")",
          type = "transport",
        })
      end)
    end
    return
  end

  local sys_ok, sys_result = pcall(function()
    return vim.system(cmd, sys_opts):wait()
  end)
  if not sys_ok then
    return nil, {
      message = "jira.nvim: failed to invoke curl - is it installed and on $PATH? (" .. tostring(sys_result) .. ")",
      type = "transport",
    }
  end
  return parse_result(sys_result)
end

return M
