-- Tiny async test harness: no dependencies, so it runs anywhere `nvim --headless` does (and in CI).
-- Tests run inside a coroutine; `wait_until` yields to Neovim's event loop, so typed keys, debounce
-- timers and LSP responses are all processed for real between steps.
local H = {}

local results, current = {}, nil
local tests = {}

function H.test(name, fn) table.insert(tests, { name = name, fn = fn }) end

function H.eq(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    error(('%sexpected %s, got %s'):format(msg and (msg .. ': ') or '', vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

function H.ok(value, msg)
  if not value then error(msg or 'expected a truthy value', 2) end
end

-- Yield to the event loop until fn() is truthy (or the timeout passes). Returns fn()'s last value.
function H.wait_until(fn, ms)
  local deadline = vim.uv.now() + (ms or 2000)
  local value = fn()
  while not value and vim.uv.now() < deadline do
    vim.defer_fn(function() coroutine.resume(current) end, 5)
    coroutine.yield()
    value = fn()
  end
  return value
end

function H.sleep(ms)
  local done = false
  vim.defer_fn(function() done = true end, ms)
  H.wait_until(function() return done end, ms + 1000)
end

-- Type keys as a user would (processed by the main loop, so autocmds and mappings fire).
function H.feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 't', false)
  H.sleep(1)
end

-- An in-process fake language server. `opts.complete(params)` returns the completion result;
-- `opts.resolve(item)` the resolved item. Every request is recorded in `server.requests`.
function H.fake_server(opts)
  opts = opts or {}
  local server = { requests = {} }
  server.cmd = function()
    local closing, id = false, 0
    return {
      request = function(method, params, callback)
        id = id + 1
        table.insert(server.requests, { method = method, params = params })
        local reply
        if method == 'initialize' then
          reply = { capabilities = { completionProvider = {
            triggerCharacters = opts.trigger_characters or { '.', ' ', '(' },
            resolveProvider = opts.resolve ~= nil,
          } } }
        elseif method == 'textDocument/completion' then
          reply = opts.complete and opts.complete(params) or { items = {} }
        elseif method == 'completionItem/resolve' then
          reply = opts.resolve and opts.resolve(params) or params
        end
        vim.schedule(function() callback(nil, reply) end)
        return true, id
      end,
      notify = function() return true end,
      is_closing = function() return closing end,
      terminate = function() closing = true end,
    }
  end
  function server.count(method)
    return #vim.tbl_filter(function(r) return r.method == method end, server.requests)
  end
  return server
end

-- A fresh buffer with the fake server attached.
function H.buffer(server, filetype)
  vim.cmd('enew!')
  vim.bo.filetype = filetype or 'cs'
  local id = vim.lsp.start({ name = 'fake', cmd = server.cmd, root_dir = vim.fn.getcwd() }, { reuse_client = function() return false end })
  H.wait_until(function() return vim.lsp.get_client_by_id(id) and vim.lsp.get_client_by_id(id).initialized end)
  return id
end

-- Back to a clean state between tests: normal mode, no clients, fresh module.
function H.reset()
  if vim.fn.mode() ~= 'n' then vim.cmd('stopinsert') end
  for _, c in ipairs(vim.lsp.get_clients()) do c:stop(true) end
  H.sleep(20)
  package.loaded['mini_complete'] = nil
  return require('mini_complete')
end

function H.labels(items)
  return vim.tbl_map(function(i) return i.label end, items)
end

function H.run()
  current = coroutine.create(function()
    local failed = 0
    for i, t in ipairs(tests) do
      local ok, err = pcall(t.fn)
      if ok then
        table.insert(results, ('ok %d - %s'):format(i, t.name))
      else
        failed = failed + 1
        table.insert(results, ('not ok %d - %s\n  # %s'):format(i, t.name, tostring(err):gsub('\n', '\n  # ')))
      end
      H.reset()
    end
    table.insert(results, ('1..%d'):format(#tests))
    table.insert(results, ('# pass %d, fail %d'):format(#tests - failed, failed))
    io.stdout:write(table.concat(results, '\n') .. '\n')
    vim.cmd(failed == 0 and 'qa!' or 'cq!')
  end)
  vim.schedule(function()
    local ok, err = coroutine.resume(current)
    if not ok then io.stdout:write('harness error: ' .. tostring(err) .. '\n'); vim.cmd('cq!') end
  end)
end

return H
