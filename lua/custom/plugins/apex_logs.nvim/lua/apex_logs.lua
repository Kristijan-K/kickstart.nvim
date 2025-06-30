---@alias DMLBlock { code_row: string, op: string, obj: string, rows: integer, ns: integer, ns2?: integer, ms?: number, log_idx: integer, matched: boolean, rest: string }
---@alias DMLHighlightSpan { line: integer, from: integer, to: integer }
---@alias SOQLBlock { code_row: string, soql: string, rows: string, ms: number, group_total: integer, orig_idx: integer, exec_num: integer }
---@alias SOQLHighlightSpan { line: integer, from: integer, to: integer }
---@alias UserDebugHighlightSpan { line: integer, from: integer, to: integer }
---@class TreeNode
---@field tag string
---@field name string
---@field code_row? string
---@field start_ns number
---@field end_ns number
---@field duration number
---@field children TreeNode[]
---@field parent? TreeNode
---@field expanded? boolean
---@field line_idx integer
---@field is_dummy? boolean

local M = {}
local api = vim.api

---@param line string
---@return boolean
local function is_timestamped_line(line)
  return line:match '^%d%d:%d%d:%d%d'
end

local function ensure_teal_hl()
  vim.cmd 'highlight default ApexLogTeal guifg=#20B2AA ctermfg=37'
end

---@param lines string[]
---@return string[] dml_lines, DMLHighlightSpan[] highlight_spans
local function extract_dml_blocks(lines)
  local dml_blocks = {}
  local dml_pending = {}
  local dml_type_counts = {}

  for idx, line in ipairs(lines) do
    if line:find('|DML_BEGIN|', 1, true) then
      local ns1 = tonumber(line:match '%((%d+)%)')
      local code_row = line:match '|DML_BEGIN|%[(%d+)%]'
      local op = line:match 'Op:([^|]+)'
      local obj = line:match 'Type:([^|]+)'
      local rows = tonumber(line:match 'Rows:(%d+)' or '0')
      -- everything after [CODE_ROW]| for the right side (so [40]|Op:Insert|Type:Mariposa_Order__c|Rows:1 -> Op:Insert|Type:Mariposa_Order__c|Rows:1)
      local rest = line:match '|DML_BEGIN|%[%d+%]|(.+)'
      table.insert(dml_pending, {
        code_row = code_row or '',
        op = op or '',
        obj = obj or '',
        rows = rows,
        ns = ns1 or 0,
        log_idx = idx,
        matched = false,
        rest = rest or '',
      })
    elseif line:find('|DML_END|', 1, true) then
      local ns2 = tonumber(line:match '%((%d+)%)')
      local code_row = line:match '|DML_END|%[(%d+)%]'
      -- Find the first unmatched BEGIN with same code_row
      for _, entry in ipairs(dml_pending) do
        if not entry.matched and entry.code_row == code_row then
          entry.ns2 = ns2 or 0
          entry.ms = entry.ns2 > entry.ns and (entry.ns2 - entry.ns) / 1e6 or 0
          entry.matched = true
          break
        end
      end
    end
  end

  -- Only keep matched ones
  for _, entry in ipairs(dml_pending) do
    if entry.matched then
      table.insert(dml_blocks, entry)
      local k = (entry.op or '') .. '(' .. (entry.obj or '') .. ')'
      dml_type_counts[k] = (dml_type_counts[k] or 0) + 1
    end
  end

  -- Sort by Rows, descending
  table.sort(dml_blocks, function(a, b)
    return a.rows > b.rows
  end)

  -- Type breakdown summary
  local typelines = {}
  for k, v in pairs(dml_type_counts) do
    table.insert(typelines, ('%s: %d'):format(k, v))
  end
  table.sort(typelines)

  -- Format
  local flat = {}
  if next(typelines) then
    table.insert(flat, '-- DML Statement Types: ' .. table.concat(typelines, ', ') .. ' --')
  else
    table.insert(flat, 'No DML statements found.')
  end

  local highlight_spans = {}
  for idx, entry in ipairs(dml_blocks) do
    local indexstr = ('%d. '):format(idx)
    local code_str = entry.code_row ~= '' and ('[' .. entry.code_row .. ']') or ''
    local code_str2 = code_str ~= '' and (code_str .. ' | ') or ''
    local index_start = #indexstr
    local index_end = index_start + #code_str
    local rowpart = 'Rows:' .. tostring(entry.rows)
    local ms_part = ('%.2fms'):format(entry.ms or 0)
    local line = indexstr .. code_str2 .. entry.rest:gsub('Rows:%d+', rowpart) .. ' | ' .. ms_part
    table.insert(flat, line)
    if #code_str > 0 then
      table.insert(highlight_spans, { line = #flat - 1, from = index_start, to = index_end })
    end
  end
  return flat, highlight_spans
end

---@param lines string[]
---@return string[] user_debug_lines, UserDebugHighlightSpan[] highlight_spans
local function extract_user_debug_blocks(lines)
  local blocks = {}
  local in_debug = false
  local current = {}
  local highlight_spans = {}

  for idx, line in ipairs(lines) do
    if not in_debug and line:find('|USER_DEBUG|', 1, true) then
      in_debug = true
      current = { line }
    elseif in_debug and is_timestamped_line(line) then
      table.insert(blocks, vim.tbl_extend('force', {}, current))
      in_debug = false
      current = {}
    elseif in_debug then
      table.insert(current, line)
    end
  end
  if in_debug and #current > 0 then
    table.insert(blocks, current)
  end

  local flat = {}
  for idx, block in ipairs(blocks) do
    if #block > 0 then
      local first_line = block[1]
      local after_user_debug = first_line:match '|USER_DEBUG|(.*)'
      local line_number = after_user_debug and after_user_debug:match '%[(%d+)%]'
      local line_number_str = line_number and ('[' .. line_number .. ']') or ''
      local rest = after_user_debug and after_user_debug:gsub('^%s*%[%d+%]%|?DEBUG%|?', '') or ''
      local prefix = ('%d. '):format(idx)
      local line_text = prefix .. line_number_str .. rest
      table.insert(flat, line_text)
      if #line_number_str > 0 then
        table.insert(highlight_spans, { line = #flat - 1, from = #prefix, to = #prefix + #line_number_str })
      end
      for j = 2, #block do
        table.insert(flat, block[j])
      end
      table.insert(flat, '-----------------------------')
    end
  end
  if #flat > 0 then
    table.remove(flat, #flat)
  end
  return flat, highlight_spans
end

---@param lines string[]
---@param sort_mode string
---@return string[] soql_lines, SOQLHighlightSpan[] highlight_spans
local function extract_soql_blocks(lines, sort_mode)
  local blocks = {}
  local soql_counts = {}
  local in_begin = false
  local begin_data = nil

  for idx, line in ipairs(lines) do
    if line:find('|SOQL_EXECUTE_BEGIN|', 1, true) then
      local ns1 = line:match '%((%d+)%)'
      local code_row = line:match '|SOQL_EXECUTE_BEGIN|%[(%d+)%]'
      local after = line:match '|SOQL_EXECUTE_BEGIN|%[%d+%]|[^|]*|([^|]+)'
      local soql = after and after:match '[SELECT].*$'
      begin_data = { line_idx = idx, code_row = code_row, ns = tonumber(ns1), soql = soql or '', raw_line = line }
      in_begin = true
    elseif in_begin and line:find('|SOQL_EXECUTE_END|', 1, true) then
      local end_code_row = line:match '|SOQL_EXECUTE_END|%[(%d+)%]'
      if end_code_row == begin_data.code_row then
        local ns2 = line:match '%((%d+)%)'
        local ms = 0
        if begin_data.ns and ns2 then
          ms = (tonumber(ns2) - begin_data.ns) / 1e6
        end
        local rows = line:match 'Rows:(%d+)'
        local soql_key = begin_data.soql or ''
        soql_counts[soql_key] = (soql_counts[soql_key] or 0) + 1
        table.insert(blocks, {
          code_row = begin_data.code_row or '',
          soql = soql_key,
          rows = rows or '0',
          ms = ms,
          group_total = 0,
          orig_idx = idx,
        })
      end
      in_begin = false
      begin_data = nil
    end
  end

  -- compute total soql counts
  local soql_count_map = {}
  for i, block in ipairs(blocks) do
    local key = block.soql
    soql_count_map[key] = (soql_count_map[key] or 0) + 1
    block.exec_num = soql_count_map[key]
    block.group_total = soql_counts[key] or 1
  end

  -- Sort according to mode
  if sort_mode == 'execs' then
    table.sort(blocks, function(a, b)
      if a.group_total ~= b.group_total then
        return a.group_total > b.group_total
      elseif a.ms ~= b.ms then
        return a.ms > b.ms
      elseif tonumber(a.rows) ~= tonumber(b.rows) then
        return tonumber(a.rows) > tonumber(b.rows)
      else
        return a.orig_idx < b.orig_idx
      end
    end)
  elseif sort_mode == 'rows' then
    table.sort(blocks, function(a, b)
      if tonumber(a.rows) ~= tonumber(b.rows) then
        return tonumber(a.rows) > tonumber(b.rows)
      elseif a.group_total ~= b.group_total then
        return a.group_total > b.group_total
      elseif a.ms ~= b.ms then
        return a.ms > b.ms
      else
        return a.orig_idx < b.orig_idx
      end
    end)
  elseif sort_mode == 'ms' then
    table.sort(blocks, function(a, b)
      if a.ms ~= b.ms then
        return a.ms > b.ms
      elseif a.group_total ~= b.group_total then
        return a.group_total > b.group_total
      elseif tonumber(a.rows) ~= tonumber(b.rows) then
        return tonumber(a.rows) > tonumber(b.rows)
      else
        return a.orig_idx < b.orig_idx
      end
    end)
  end

  local sort_label = ({
    execs = '-- Sorted by: Executions --',
    rows = '-- Sorted by: Rows --',
    ms = '-- Sorted by: Time --',
  })[sort_mode or 'execs'] or ''

  -- Format
  local flat, highlight_spans = { sort_label }, {}
  for idx, block in ipairs(blocks) do
    local prefix = ('%d. |'):format(idx)
    local code_row_str = block.code_row and ('[' .. block.code_row .. ']| ') or ''
    local index_start = #prefix
    local index_end = index_start + #code_row_str
    local soql_str = block.soql and block.soql or ''
    local rows_str = 'Rows:' .. block.rows
    local ms_str = ('%.2fms'):format(block.ms)
    local exec_str = ('exec %d/%d'):format(block.exec_num, block.group_total)
    local line = prefix .. code_row_str .. soql_str .. ' | ' .. rows_str .. ' | ' .. ms_str .. ' | ' .. exec_str
    table.insert(flat, line)
    if #code_row_str > 0 then
      table.insert(highlight_spans, { line = #flat - 1, from = index_start, to = index_end - 1 })
    end
  end
  if #flat == 1 then -- Only the sort label, so nothing found
    flat = { 'No SOQL statements found.' }
    highlight_spans = {}
  end
  return flat, highlight_spans
end

---@param lines string[]
---@return string[] exception_lines
local function extract_exception_blocks(lines)
  local processed_unique_lines = {}
  local seen_lines = {}

  for _, line in ipairs(lines) do
    local line_lower = line:lower()
    if (line_lower:find 'exception' or line_lower:find 'error') and not line:find 'SOQL_EXECUTE_BEGIN' then
      local processed_line = line
      local first_pipe = line:find '|'
      if first_pipe then
        local second_pipe = line:find('|', first_pipe + 1)
        if second_pipe then
          processed_line = line:sub(second_pipe + 1)
        end
      end
      -- Trim whitespace from the processed line for better comparison
      processed_line = processed_line:gsub('^%s*(.-)%s*$', '%1')
      if not seen_lines[processed_line] then
        table.insert(processed_unique_lines, processed_line)
        seen_lines[processed_line] = true
      end
    end
  end

  -- Sort by length in descending order for substring removal
  table.sort(processed_unique_lines, function(a, b)
    return #a > #b
  end)

  local final_exception_lines = {}
  local final_seen_lines = {}

  for _, current_line in ipairs(processed_unique_lines) do
    local is_substring = false
    for _, existing_line in ipairs(final_exception_lines) do
      if existing_line:find(current_line, 1, true) then -- Check if current_line is a substring of an existing_line
        is_substring = true
        break
      end
    end
    if not is_substring then
      table.insert(final_exception_lines, current_line)
    end
  end

  local indexed_exception_lines = {}
  if #final_exception_lines == 0 then
    table.insert(indexed_exception_lines, 'No exceptions or errors found.')
  else
    for i, line in ipairs(final_exception_lines) do
      table.insert(indexed_exception_lines, string.format('%d. %s', i, line))
    end
  end

  return indexed_exception_lines
end

---@param lines string[]
---@return string[] flat_lines, TreeNode[] line_map, TreeNode[] roots
local function extract_tree_blocks(lines)
  local open_close_map = {
    CODE_UNIT_STARTED = { close = 'CODE_UNIT_FINISHED', extract_name = true },
    METHOD_ENTRY = { close = 'METHOD_EXIT', extract_name = true },
    SYSTEM_METHOD_ENTRY = { close = 'SYSTEM_METHOD_EXIT', extract_name = true },
    SOQL_EXECUTE_BEGIN = { close = 'SOQL_EXECUTE_END', extract_name = false },
    DML_BEGIN = { close = 'DML_END', extract_name = false },
    ENTERING_MANAGED_PKG = { close = nil, extract_name = false },
    USER_DEBUG = { close = nil, extract_name = false },
  }
  local closing_to_open = {}
  for k, v in pairs(open_close_map) do
    if v.close then
      closing_to_open[v.close] = k
    end
  end

  local function get_ns(line)
    return tonumber(line:match '%((%d+)%)') or 0
  end
  local function get_code_row(line)
    return line:match '|%[(%d+)%]'
  end
  local function get_method_name(tag, line)
    if open_close_map[tag] and open_close_map[tag].extract_name then
      local parts = vim.split(line, '|')
      return vim.trim(parts[#parts] or tag)
    elseif tag == 'ENTERING_MANAGED_PKG' then
      return 'MANAGED CODE'
    elseif tag == 'SOQL_EXECUTE_BEGIN' then
      local soql = line:match '[SELECT].*'
      return soql and ('SOQL: ' .. soql) or 'SOQL'
    elseif tag == 'DML_BEGIN' then
      local op = line:match 'Op:([^|]+)'
      local obj = line:match 'Type:([^|]+)'
      return op and obj and ('DML: ' .. op .. ' ' .. obj) or 'DML'
    elseif tag == 'USER_DEBUG' then
      return 'USER_DEBUG'
    end
    return tag
  end

  -- Pass 1: Build flat list with parent/children references, expansion-ready
  local nodes = {}
  local stack = {}
  local i = 1
  while i <= #lines do
    local line = lines[i]
    local ns = get_ns(line)
    local event_tag = nil
    for tag in pairs(open_close_map) do
      if line:find('|' .. tag .. '|', 1, true) then
        event_tag = tag
        break
      end
    end
    for tag in pairs(closing_to_open) do
      if line:find('|' .. tag .. '|', 1, true) then
        event_tag = tag
        break
      end
    end

    if open_close_map[event_tag] then
      local name = get_method_name(event_tag, line)
      local code_row = get_code_row(line)
      local node = {
        tag = event_tag,
        name = name,
        code_row = code_row,
        start_ns = ns,
        end_ns = nil,
        children = {},
        parent = stack[#stack],
        line_idx = i,
        expanded = true,
      }
      table.insert(nodes, node)
      if node.parent then
        table.insert(node.parent.children, node)
      end
      if open_close_map[event_tag].close then
        table.insert(stack, node)
      end
    elseif closing_to_open[event_tag] then
      local open_tag = closing_to_open[event_tag]
      for j2 = #stack, 1, -1 do
        local n = stack[j2]
        if n and n.tag == open_tag and not n.end_ns then
          n.end_ns = ns
          table.remove(stack, j2)
          break
        end
      end
    end
    i = i + 1
  end

  -- Set .end_ns for single/no-close nodes as next node, else self
  for k, node in ipairs(nodes) do
    if not node.end_ns then
      local next = nodes[k + 1]
      node.end_ns = next and next.start_ns or node.start_ns
    end
  end

  -- Aggregation pass: flatten all consecutive MANAGED CODE siblings under the same parent into a single node
  local function aggregate_managed_code(children)
    local aggregated = {}
    local idx = 1
    while idx <= #children do
      local node = children[idx]
      if node.tag == 'ENTERING_MANAGED_PKG' then
        -- start grouping
        local group_start = idx
        local group_end = idx
        while group_end + 1 <= #children and children[group_end + 1].tag == 'ENTERING_MANAGED_PKG' do
          group_end = group_end + 1
        end
        if group_end > group_start then
          local first = children[group_start]
          local last = children[group_end]
          table.insert(aggregated, {
            tag = 'ENTERING_MANAGED_PKG',
            name = 'MANAGED CODE (' .. (group_end - group_start + 1) .. ' seq.)',
            code_row = nil,
            start_ns = first.start_ns,
            end_ns = last.end_ns,
            children = {},
            parent = first.parent,
            expanded = true,
          })
        else
          table.insert(aggregated, node)
        end
        idx = group_end + 1
      else
        -- For tree nodes, recurse into its children
        if node.children and #node.children > 0 then
          node.children = aggregate_managed_code(node.children)
        end
        table.insert(aggregated, node)
        idx = idx + 1
      end
    end
    return aggregated
  end

  -- Top-level root nodes
  local roots = {}
  for _, n in ipairs(nodes) do
    if not n.parent then
      table.insert(roots, n)
    end
  end
  roots = aggregate_managed_code(roots)
  -- and for all descendant nodes:
  local function aggregate_descendants(node)
    if node.children and #node.children > 0 then
      node.children = aggregate_managed_code(node.children)
      for _, child in ipairs(node.children) do
        aggregate_descendants(child)
      end
    end
  end
  for _, r in ipairs(roots) do
    aggregate_descendants(r)
  end

  -- Compute durations for all nodes, collect them for "10 Longest"
  local durations = {}
  local function collect_durations(node)
    node.duration = ((node.end_ns or node.start_ns) - node.start_ns) / 1e6
    table.insert(durations, { node = node, ms = node.duration })
    if node.children then
      for _, child in ipairs(node.children) do
        collect_durations(child)
      end
    end
  end
  for _, r in ipairs(roots) do
    collect_durations(r)
  end
  table.sort(durations, function(a, b)
    return a.ms > b.ms
  end)

  -- 10 Longest
  local longest = {}
  for idx = 1, math.min(10, #durations) do
    local node = durations[idx].node
    local cr = node.code_row and (' [' .. node.code_row .. ']') or ''
    table.insert(longest, string.format('%2d. %s%s | %.2fms', idx, node.name, cr, node.duration))
  end

  -- Render (with collapsible/expandable support)
  local function render(node, depth, out_lines, line_map)
    table.insert(line_map, node)
    local cr = node.code_row and (' [' .. node.code_row .. ']') or ''
    local indent = string.rep('\t', depth)
    local mark = (#node.children > 0) and (node.expanded and '▼ ' or '▶ ') or '  '
    local line = indent .. mark .. node.name .. cr .. string.format(' | %.2fms', node.duration)
    table.insert(out_lines, line)
    if node.expanded and node.children then
      for _, child in ipairs(node.children) do
        render(child, depth + 1, out_lines, line_map)
      end
    end
  end

  local flat, line_map = {}, {}
  if #longest > 0 then
    for _, l in ipairs(longest) do
      table.insert(flat, l)
    end
    table.insert(flat, '---- 10 Longest Operations ----')
    table.insert(line_map, { is_dummy = true })
  end
  for _, n in ipairs(roots) do
    render(n, 0, flat, line_map)
  end
  if #flat == 0 then
    table.insert(flat, 'No method stack information found.')
    table.insert(line_map, {})
  end

  return flat, line_map, roots
end

function M.analyzeLogs()
  ensure_teal_hl()
  local orig_lines = api.nvim_buf_get_lines(0, 0, -1, false)

  local tab_bufs = {}
  local sort_modes = { 'execs', 'rows', 'ms' }
  local sort_mode_idx = 1
  local soql_sort_mode = sort_modes[sort_mode_idx]
  local user_debug_lines, userdebug_spans = extract_user_debug_blocks(orig_lines)
  local soql_lines, soql_spans = extract_soql_blocks(orig_lines, soql_sort_mode)

  local dml_lines, dml_spans = extract_dml_blocks(orig_lines)
  local exception_lines = extract_exception_blocks(orig_lines)

  local tree_nodes
  local function render_tree_and_update_buf()
    local lines, map, nodes = extract_tree_blocks(orig_lines)
    tree_nodes = nodes
    tree_lines = lines
    tree_line_map = map
    api.nvim_buf_set_lines(tab_bufs[2], 0, -1, false, tree_lines)
  end

  local tab_titles = { 'User Debug', 'Method Tree', 'SOQL', 'DML', 'Exceptions' }

  for i, title in ipairs(tab_titles) do
    local buf = api.nvim_create_buf(false, true)
    if i == 1 then
      api.nvim_buf_set_lines(buf, 0, -1, false, user_debug_lines)
    elseif i == 3 then
      api.nvim_buf_set_lines(buf, 0, -1, false, soql_lines)
    elseif i == 4 then
      api.nvim_buf_set_lines(buf, 0, -1, false, dml_lines)
    elseif i == 5 then
      api.nvim_buf_set_lines(buf, 0, -1, false, exception_lines)
    else
      api.nvim_buf_set_lines(buf, 0, -1, false, { 'This is the [' .. title .. '] tab.' })
    end
    tab_bufs[i] = buf
  end

  render_tree_and_update_buf()

  api.nvim_buf_set_keymap(tab_bufs[2], 'n', 'z', '', {
    noremap = true,
    nowait = true,
    callback = function()
      local cur_line = vim.api.nvim_win_get_cursor(win)[1]
      local node = tree_line_map[cur_line]
      if not node or node.is_dummy then
        return
      end
      -- Collapse/expand logic: toggle parent if this isn't root or dummy
      if node.parent then
        node.parent.expanded = not node.parent.expanded
        render_tree_and_update_buf()
        -- Set cursor to parent line if collapsed, otherwise stay
        for i, n in ipairs(tree_line_map) do
          if n == (node.parent.expanded and node or node.parent) then
            api.nvim_win_set_cursor(win, { i, 0 })
            break
          end
        end
      elseif node.children and #node.children > 0 then
        -- Root line: allow toggle on self
        node.expanded = not node.expanded
        render_tree_and_update_buf()
      end
    end,
  })

  -- Floating window setup
  local width = math.floor(vim.o.columns * 0.95)
  local height = math.floor(vim.o.lines * 0.90)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  local win = api.nvim_open_win(tab_bufs[1], true, {
    relative = 'editor',
    style = 'minimal',
    border = 'rounded',
    row = row,
    col = col,
    width = width,
    height = height,
  })
  vim.wo[win].winfixwidth = true
  vim.wo[win].winfixheight = true

  local function get_tabline(active_idx)
    local parts = {}
    for i, title in ipairs(tab_titles) do
      if i == active_idx then
        table.insert(parts, '%#TabLineSel#' .. title .. '%*')
      else
        table.insert(parts, '%#TabLine#' .. title .. '%*')
      end
    end
    return table.concat(parts, ' | ')
  end

  local ns = api.nvim_create_namespace 'apex_log_teal'
  local current_tab = 1
  local function clear_highlights()
    for _, buf in ipairs(tab_bufs) do
      api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
  end

  local function add_highlights(tab_idx)
    clear_highlights()
    local spans = (tab_idx == 1 and userdebug_spans) or (tab_idx == 3 and soql_spans) or (tab_idx == 4 and dml_spans) or {}
    local buf = tab_bufs[tab_idx]
    for _, span in ipairs(spans or {}) do
      api.nvim_buf_add_highlight(buf, ns, 'ApexLogTeal', span.line, span.from, span.to)
    end
  end
  local function refresh_soql_buf()
    local soql_lines2, soql_spans2 = extract_soql_blocks(orig_lines, soql_sort_mode)
    api.nvim_buf_set_lines(tab_bufs[3], 0, -1, false, soql_lines2)
    soql_spans = soql_spans2
    if current_tab == 3 then
      add_highlights(3)
    end
  end
  local function switch_tab(idx)
    if idx < 1 then
      idx = #tab_bufs
    end
    if idx > #tab_bufs then
      idx = 1
    end
    api.nvim_win_set_buf(win, tab_bufs[idx])
    vim.wo[win].winbar = get_tabline(idx)
    current_tab = idx
    add_highlights(current_tab)
  end

  switch_tab(1)
  add_highlights(1)

  for i, buf in ipairs(tab_bufs) do
    api.nvim_buf_set_keymap(buf, 'n', '<Tab>', '', {
      noremap = true,
      nowait = true,
      callback = function()
        switch_tab(current_tab + 1)
      end,
    })
    api.nvim_buf_set_keymap(buf, 'n', '<S-Tab>', '', {
      noremap = true,
      nowait = true,
      callback = function()
        switch_tab(current_tab - 1)
      end,
    })
    api.nvim_buf_set_keymap(buf, 'n', 'q', '', {
      noremap = true,
      nowait = true,
      callback = function()
        if api.nvim_win_is_valid(win) then
          api.nvim_win_close(win, true)
        end
        for _, b in ipairs(tab_bufs) do
          pcall(api.nvim_buf_delete, b, { force = true })
        end
      end,
    })
    if i == 3 then
      -- SOQL tab: toggle sort mode with 'r'
      api.nvim_buf_set_keymap(buf, 'n', 'r', '', {
        noremap = true,
        nowait = true,
        callback = function()
          sort_mode_idx = (sort_mode_idx % #sort_modes) + 1
          soql_sort_mode = sort_modes[sort_mode_idx]
          refresh_soql_buf()
        end,
      })
    end
  end
end

return M
