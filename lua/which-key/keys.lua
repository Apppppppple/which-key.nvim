local Tree = require("which-key.tree")
local Util = require("which-key.util")
local Config = require("which-key.config")

-- secret character that will be used to create <nop> mappings
local secret = "Þ"

---@class Keys
local M = {}

M.functions = {}

function M.setup()
  local builtin_ops = require("which-key.plugins.presets").operators
  local mappings = {}
  for op, label in pairs(Config.options.operators) do
    if builtin_ops[op] then
      mappings[op] = { name = label, i = { name = "inside" }, a = { name = "around" } }
    end
  end
  M.register(mappings, { mode = "n" })
  M.register({ i = { name = "inside" }, a = { name = "around" } }, { mode = "v" })
end

function M.get_operator(prefix)
  for op, _ in pairs(Config.options.operators) do if prefix:sub(1, #op) == op then return op end end
end

function M.process_motions(ret, mode, prefix, buf)
  local operator = mode == "v" and "" or M.get_operator(prefix)
  if (mode == "n" or mode == "v") and operator then
    local op_prefix = prefix:sub(#operator + 1)
    local op_count = op_prefix:match("^(%d+)")
    if op_count then op_prefix = op_prefix:sub(#op_count + 1) end
    local op_results = M.get_mappings("o", op_prefix, buf)

    if not ret.mapping and op_results.mapping then
      ret.mapping = op_results.mapping
      ret.mapping.prefix = prefix
      ret.keys = Util.parse_keys(ret.prefix)
    end

    for _, mapping in pairs(op_results.mappings) do
      mapping.prefix = operator .. (op_count or "") .. mapping.prefix
      mapping.keys = Util.parse_keys(mapping.prefix)
      table.insert(ret.mappings, mapping)
    end
  end
end

---@return MappingGroup
function M.get_mappings(mode, prefix, buf)
  ---@class MappingGroup
  ---@field mode string
  ---@field prefix string
  ---@field buf number
  ---@field mapping Mapping
  ---@field mappings VisualMapping[]
  local ret
  ret = { mapping = nil, mappings = {}, mode = mode, buf = buf, prefix = prefix }

  local prefix_len = #Util.parse_keys(prefix).nvim

  ---@param node Node
  local function add(node)
    if node then
      if node.mapping then
        ret.mapping = vim.tbl_deep_extend("force", {}, ret.mapping or {}, node.mapping)
      end
      for k, child in pairs(node.children) do
        if child.mapping and child.mapping.label ~= "which_key_ignore" then
          ret.mappings[k] = vim.tbl_deep_extend("force", {}, ret.mappings[k] or {}, child.mapping)
        end
      end
    end
  end

  add(M.get_tree(mode).tree:get(prefix))
  add(M.get_tree(mode, buf).tree:get(prefix))

  -- Run a plugin if needed
  if ret.mapping and ret.mapping.plugin then require("which-key.plugins").invoke(ret) end

  -- Handle motions
  M.process_motions(ret, mode, prefix, buf)

  -- Fix labels
  local tmp = {}
  for _, value in pairs(ret.mappings) do
    value.key = value.keys.nvim[prefix_len + 1]
    if value.group then
      value.label = value.label or "+prefix"
      value.label = value.label:gsub("^%+", "")
      value.label = Config.options.icons.group .. value.label
    else
      if not value.label then
        value.label = value.cmd or ""
        for _, v in ipairs(Config.options.hidden) do value.label = value.label:gsub(v, "") end
      end
    end
    table.insert(tmp, value)
  end

  -- Sort items, but not for plugins
  if not (ret.mapping and ret.mapping.plugin) then
    table.sort(tmp, function(a, b)
      if a.group == b.group then
        local ak = (a.key or ""):lower()
        local bk = (b.key or ""):lower()
        local aw = ak:match("[a-z]") and 1 or 0
        local bw = bk:match("[a-z]") and 1 or 0
        if aw == bw then return ak < bk end
        return aw < bw
      else
        return (a.group and 1 or 0) < (b.group and 1 or 0)
      end
    end)
  end
  ret.mappings = tmp

  return ret
end

---@param mappings Mapping[]
---@return Mapping[]
function M.parse_mappings(mappings, value, prefix)
  prefix = prefix or ""
  if type(value) == "string" then
    table.insert(mappings, { prefix = prefix, label = value })
  elseif type(value) == "table" then
    if #value == 0 then
      -- key group
      for k, v in pairs(value) do
        if k ~= "name" then M.parse_mappings(mappings, v, prefix .. k) end
      end
      if prefix ~= "" then
        if value.name then value.name = value.name:gsub("^%+", "") end
        table.insert(mappings, { prefix = prefix, label = value.name, group = true })
      end
    else
      -- key mapping
      ---@type Mapping
      local mapping
      mapping = { prefix = prefix, opts = {}, buf = M.get_buf_option(value) }
      for k, v in pairs(value) do
        if k == 1 then
          mapping.label = v
        elseif k == 2 then
          mapping.cmd = mapping.label
          mapping.label = v
        elseif k == "noremap" then
          mapping.opts.noremap = v
        elseif k == "silent" then
          mapping.opts.silent = v
        elseif k == "plugin" then
          mapping.group = true
          mapping.plugin = v
        else
          error("Invalid key mapping: " .. vim.inspect(value))
        end
      end
      if mapping.cmd and type(mapping.cmd) == "function" then
        table.insert(M.functions, mapping.cmd)
        mapping.cmd = string.format([[<cmd>lua require("which-key").execute(%d)<cr>]], #M.functions)
      end
      table.insert(mappings, mapping)
    end
  else
    error("Invalid mapping " .. vim.inspect(value))
  end
  return mappings
end

function M.get_buf_option(opts)
  for _, k in pairs({ "buffer", "bufnr", "buf" }) do
    if opts[k] then
      local v = opts[k]
      opts[k] = nil
      if k == "buffer" then
        return v
      elseif k == "bufnr" or k == "buf" then
        Util.warn(string.format([[please use "buffer" instead of %q for buffer mappings]], k))
        return v
      end
    end
  end
end

---@type table<string, MappingTree>
M.mappings = {}

function M.register(mappings, opts)
  opts = opts or {}

  local prefix = opts.prefix or ""
  local mode = opts.mode or "n"

  opts.buffer = M.get_buf_option(opts)

  mappings = M.parse_mappings({}, mappings, prefix)

  -- always create the root node for the mode, even if there's no mappings,
  -- to ensure we have at least a trigger hooked for non documented keymaps
  M.get_tree(mode)

  for _, mapping in pairs(mappings) do
    if opts.buffer and not mapping.buf then mapping.buf = opts.buffer end
    mapping.keys = Util.parse_keys(mapping.prefix)
    if mapping.cmd then
      mapping.opts = vim.tbl_deep_extend("force", { silent = true, noremap = true }, opts,
                                         mapping.opts or {})
      local keymap_opts = {
        silent = mapping.opts.silent,
        noremap = mapping.opts.noremap,
        nowait = mapping.opts.nowait or false,
      }
      if mapping.cmd:lower():sub(1, #("<plug>")) == "<plug>" then keymap_opts.noremap = false end
      if mapping.buf ~= nil then
        vim.api.nvim_buf_set_keymap(mapping.buf, mode, mapping.prefix, mapping.cmd, keymap_opts)
      else
        vim.api.nvim_set_keymap(mode, mapping.prefix, mapping.cmd, keymap_opts)
      end
    end
    M.get_tree(mode, mapping.buf).tree:add(mapping)
  end
end

M.hooked = {}

function M.hook_id(prefix, mode, buf) return mode .. (buf or "") .. Util.t(prefix) end

function M.is_hooked(prefix, mode, buf) return M.hooked[M.hook_id(prefix, mode, buf)] end

function M.hook_del(prefix, mode, buf)
  local id = M.hook_id(prefix, mode, buf)
  M.hooked[id] = nil
  if buf then
    pcall(vim.api.nvim_buf_del_keymap, buf, mode, prefix)
    pcall(vim.api.nvim_buf_del_keymap, buf, mode, prefix .. secret)
  else
    pcall(vim.api.nvim_del_keymap, mode, prefix)
    pcall(vim.api.nvim_del_keymap, mode, prefix .. secret)
  end
end

function M.hook_add(prefix, mode, buf, secret_only)
  -- Check if we need to create the hook
  if type(Config.options.triggers) == "string" and Config.options.triggers ~= "auto" then
    if Util.t(prefix) ~= Util.t(Config.options.triggers) then return end
  end
  if type(Config.options.triggers) == "table" then
    local ok = false
    for _, trigger in pairs(Config.options.triggers) do
      if Util.t(trigger) == Util.t(prefix) then
        ok = true
        break
      end
    end
    if not ok then return end
  end
  -- never hook into operator pending mode
  -- this is handled differently
  if mode == "o" then return end

  local opts = { noremap = true, silent = true }
  local id = M.hook_id(prefix, mode, buf)
  local id_global = M.hook_id(prefix, mode)
  -- hook up if needed
  if not M.hooked[id] and not M.hooked[id_global] then
    local cmd = [[<cmd>lua require("which-key").show(%q, {mode = %q, auto = true})<cr>]]
    cmd = string.format(cmd, prefix, mode)
    -- map group triggers and nops
    -- nops are needed, so that WhichKey always respects timeoutlen
    if buf then
      if secret_only ~= true then vim.api.nvim_buf_set_keymap(buf, mode, prefix, cmd, opts) end
      vim.api.nvim_buf_set_keymap(buf, mode, prefix .. secret, "<nop>", opts)
    else
      if secret_only ~= true then vim.api.nvim_set_keymap(mode, prefix, cmd, opts) end
      vim.api.nvim_set_keymap(mode, prefix .. secret, "<nop>", opts)
    end
    M.hooked[id] = true
  end
end

function M.update(buf)
  for k, tree in pairs(M.mappings) do
    if tree.buf and not vim.api.nvim_buf_is_valid(tree.buf) then
      -- remove group for invalid buffers
      M.mappings[k] = nil
    elseif (not buf) or (not tree.buf) or buf == tree.buf then
      -- only update buffer maps, if:
      -- 1. we dont pass a buffer
      -- 2. this is a global node
      -- 3. this is a local buffer node for the passed buffer
      M.update_keymaps(tree.mode, tree.buf)
      M.add_hooks(tree.mode, tree.buf, tree.tree.root)
    end
  end
end

---@param node Node
function M.add_hooks(mode, buf, node, secret_only)
  if not node.mapping then
    node.mapping = { prefix = node.prefix, group = true, keys = Util.parse_keys(node.prefix) }
  end
  if node.prefix ~= "" and node.mapping.group == true and not node.mapping.cmd then
    -- first non-cmd level, so create hook and make all decendents secret only
    M.hook_add(node.prefix, mode, buf, secret_only)
    secret_only = true
  end
  for _, child in pairs(node.children) do M.add_hooks(mode, buf, child, secret_only) end
end

function M.dump()
  local ok = {}
  local todo = {}
  for _, tree in pairs(M.mappings) do
    M.update_keymaps(tree.mode, tree.buf)
    tree.tree:walk( ---@param node Node
    function(node)
      if node.mapping then
        if node.mapping.label then
          ok[node.mapping.prefix] = true
          todo[node.mapping.prefix] = nil
        elseif not ok[node.mapping.prefix] then
          todo[node.mapping.prefix] = { node.mapping.cmd or "" }
        end
      end
    end)
  end
  return todo
end

function M.check_health()
  vim.fn["health#report_start"]("WhichKey: checking conflicting keymaps")
  for _, tree in pairs(M.mappings) do
    M.update_keymaps(tree.mode, tree.buf)
    tree.tree:walk( ---@param node Node
    function(node)
      local count = 0
      for _ in pairs(node.children) do count = count + 1 end

      local auto_prefix = not node.mapping or (node.mapping.group == true and not node.mapping.cmd)
      if node.prefix ~= "" and count > 0 and not auto_prefix then
        local msg = ("conflicting keymap exists for mode **%q**, lhs: **%q**"):format(tree.mode,
                                                                                      node.mapping
                                                                                        .prefix)
        vim.fn["health#report_warn"](msg)
        local cmd = node.mapping.cmd or " "
        vim.fn["health#report_info"](("rhs: `%s`"):format(cmd))
      end
    end)
  end
end

function M.get_tree(mode, buf)
  Util.check_mode(mode, buf)
  local idx = mode .. (buf or "")
  if not M.mappings[idx] then M.mappings[idx] = { mode = mode, buf = buf, tree = Tree:new() } end
  return M.mappings[idx]
end

function M.is_hook(prefix, cmd)
  -- skip mappings with our secret nop command
  local has_secret = prefix:find(secret)
  -- skip auto which-key mappings
  local has_wk = cmd and cmd:find("which%-key") and cmd:find("auto") or false
  return has_wk or has_secret
end

---@param mode string
---@param buf number
function M.update_keymaps(mode, buf)
  ---@type Keymap
  local keymaps = buf and vim.api.nvim_buf_get_keymap(buf, mode) or vim.api.nvim_get_keymap(mode)
  local tree = M.get_tree(mode, buf).tree
  for _, keymap in pairs(keymaps) do
    local skip = M.is_hook(keymap.lhs, keymap.rhs)

    -- check if <leader> was remapped
    if not skip and Util.t(keymap.lhs) == Util.t("<leader>") then
      if Util.t(keymap.rhs) == "" then
        skip = true
      else
        Util.warn(string.format(
                    "Your <leader> key for %q mode in buf %d is currently mapped to %q. WhichKey automatically creates triggers, so please remove the mapping",
                    mode, buf or 0, keymap.rhs))
      end
    end

    if not skip then
      local mapping = {
        id = Util.t(keymap.lhs),
        prefix = keymap.lhs,
        cmd = keymap.rhs,
        keys = Util.parse_keys(keymap.lhs),
      }
      -- don't include Plug keymaps
      if mapping.keys.nvim[1]:lower() ~= "<plug>" then tree:add(mapping) end
    end
  end
end

return M
