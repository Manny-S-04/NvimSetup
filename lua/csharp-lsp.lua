-- C# language server with a safety net.
--
-- Normal case: easy-dotnet.nvim runs Roslyn (client "easy_dotnet": Roslynator, CodeLens, solution diagnostics).
-- If that client hasn't attached to a C# buffer within `timeout`, or it dies while you work, load
-- roslyn.nvim (client "roslyn", the setup that worked before) instead. Never both: if easy-dotnet's
-- Roslyn shows up after the fallback started, it is stopped.
--
-- :CSharpLsp            which server is serving C# right now
-- :CSharpLsp fallback   switch to roslyn.nvim now
-- vim.g.csharp_lsp = "roslyn.nvim" (before this runs, e.g. top of init.lua) always uses roslyn.nvim.
local M = {}

M.timeout = vim.g.csharp_lsp_fallback_timeout_ms or 30000
M.fallback_active = false

local PRIMARY, FALLBACK = "easy_dotnet", "roslyn"

local function clients(name, buf)
    return vim.lsp.get_clients({ name = name, bufnr = buf })
end

local function csharp_buffers()
    return vim.tbl_filter(function(b)
        return vim.api.nvim_buf_is_loaded(b) and (vim.bo[b].filetype == "cs" or vim.bo[b].filetype == "razor")
    end, vim.api.nvim_list_bufs())
end

function M.start_fallback(reason)
    if M.fallback_active then return end
    M.fallback_active = true
    if vim.g.csharp_lsp ~= "roslyn.nvim" then
        vim.notify(("C#: easy-dotnet's Roslyn %s — using roslyn.nvim instead"):format(reason), vim.log.levels.WARN)
    end

    for _, c in ipairs(clients(PRIMARY)) do
        c:stop()
    end
    -- Loading the plugin runs vim.lsp.enable("roslyn"); our spec's config adds the settings.
    require("lazy").load({ plugins = { "roslyn.nvim" } })
    vim.lsp.enable(FALLBACK)
    -- Attach to C# buffers that are already open (vim.lsp.enable only reacts to new FileType events).
    for _, b in ipairs(csharp_buffers()) do
        pcall(vim.api.nvim_exec_autocmds, "FileType", { group = "nvim.lsp.enable", buffer = b, modeline = false })
    end
end

local function watch(buf)
    if M.fallback_active then return end
    vim.defer_fn(function()
        if M.fallback_active or not vim.api.nvim_buf_is_valid(buf) then return end
        if #clients(PRIMARY, buf) == 0 and #clients(FALLBACK, buf) == 0 then
            M.start_fallback(("didn't start within %d s"):format(M.timeout / 1000))
        end
    end, M.timeout)
end

function M.status()
    local active = #clients(FALLBACK) > 0 and "roslyn.nvim (fallback)"
        or #clients(PRIMARY) > 0 and "easy-dotnet"
        or "none yet"
    vim.notify(("C# language server: %s%s"):format(active, M.fallback_active and " — fallback active" or ""))
end

-- Diagnostic codes to hide everywhere (Roslyn, Roslynator, any LSP). Hidden in Neovim only:
-- the build and teammates' IDEs still see them. Override with vim.g.ignored_diagnostic_codes.
--   RCS1037  Remove trailing white-space
local function hide_diagnostic_codes()
    local ignored = {}
    for _, code in ipairs(vim.g.ignored_diagnostic_codes or { "RCS1037" }) do ignored[code] = true end
    local set = vim.diagnostic.set
    vim.diagnostic.set = function(ns, bufnr, diagnostics, opts)
        if next(ignored) and diagnostics then
            diagnostics = vim.tbl_filter(function(d) return not ignored[tostring(d.code)] end, diagnostics)
        end
        return set(ns, bufnr, diagnostics, opts)
    end
end

function M.setup()
    hide_diagnostic_codes()
    local group = vim.api.nvim_create_augroup("CSharpLspFallback", { clear = true })

    vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = { "cs", "razor" },
        callback = function(args)
            if vim.g.csharp_lsp == "roslyn.nvim" then
                return M.start_fallback("is switched off (vim.g.csharp_lsp)")
            end
            watch(args.buf)
        end,
    })

    -- easy-dotnet's Roslyn went away while Neovim is still running: fall back.
    vim.api.nvim_create_autocmd("LspDetach", {
        group = group,
        callback = function(args)
            local c = vim.lsp.get_client_by_id(args.data.client_id)
            if not c or c.name ~= PRIMARY or M.fallback_active or vim.v.exiting ~= vim.NIL then return end
            vim.defer_fn(function()
                if vim.v.exiting == vim.NIL and #clients(PRIMARY) == 0 and #csharp_buffers() > 0 then
                    M.start_fallback("stopped")
                end
            end, 3000)
        end,
    })

    -- Never run both: a late easy-dotnet Roslyn is stopped once the fallback is in charge.
    vim.api.nvim_create_autocmd("LspAttach", {
        group = group,
        callback = function(args)
            local c = vim.lsp.get_client_by_id(args.data.client_id)
            if c and c.name == PRIMARY and M.fallback_active then
                vim.schedule(function() c:stop() end)
            end
        end,
    })

    vim.api.nvim_create_user_command("CSharpLsp", function(o)
        if o.args == "fallback" then
            M.start_fallback("was switched off by :CSharpLsp fallback")
        else
            M.status()
        end
    end, { nargs = "?", complete = function() return { "fallback" } end, desc = "C# language server status / fallback" })
end

return M
