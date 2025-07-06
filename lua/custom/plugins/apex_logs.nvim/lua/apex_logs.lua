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
---@field soql_count? integer
---@field dml_count? integer

local M = {}
local api = vim.api

---@param line string
---@return boolean
local function is_timestamped_line(line)
  return line:match '^%d%d:%d%d:%d%d'
end

local function ensure_teal_hl()
  vim.cmd 'highlight default ApexLogTeal guifg=#20B2AA ctermfg=37'
  vim.cmd 'highlight default ApexLogRed guifg=#FF0000 ctermfg=1'
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

local function normalize_soql(soql)
  -- Lowercase, collapse whitespace for grouping
  return (soql or ''):lower():gsub('%s+', ' ')
end

local soql_truncate = false
local soql_truncate_where = false

---@param lines string[]
---@param sort_mode string
---@return string[] soql_lines, SOQLHighlightSpan[] highlight_spans
local function extract_soql_blocks(lines, sort_mode)
  local agg = {}
  local idx_map = {}
  for idx, line in ipairs(lines) do
    if line:find('|SOQL_EXECUTE_BEGIN|', 1, true) then
      local ns1 = line:match '%((%d+)%)'
      local code_row = line:match '|SOQL_EXECUTE_BEGIN|%[(%d+)%]'
      local after = line:match '|SOQL_EXECUTE_BEGIN|%[%d+%]|[^|]*|([^|]+)'
      local soql = after and after:match '[SELECT].*$'
      idx_map[code_row or tostring(idx)] = {
        code_row = code_row or '',
        soql = soql or '',
        ns = tonumber(ns1),
        begin_idx = idx,
        rows = 0,
        ms = 0,
      }
    elseif line:find('|SOQL_EXECUTE_END|', 1, true) then
      local code_row = line:match '|SOQL_EXECUTE_END|%[(%d+)%]'
      local map = idx_map[code_row or '']
      if map and map.ns then
        local ns2 = line:match '%((%d+)%)'
        local ms = ns2 and ((tonumber(ns2) - map.ns) / 1e6) or 0
        local rows = tonumber(line:match 'Rows:(%d+)') or 0
        -- Aggregate by normalized query
        local norm = normalize_soql(map.soql)
        if norm ~= '' then
          if not agg[norm] then
            agg[norm] = {
              soql = map.soql, -- raw, first version
              code_row = map.code_row,
              count = 0,
              total_rows = 0,
              max_ms = 0,
              sample_idx = map.begin_idx,
              row_counts = {},
            }
          end
          local a = agg[norm]
          a.count = a.count + 1
          a.total_rows = a.total_rows + rows
          table.insert(a.row_counts, rows)
          if ms > a.max_ms then
            a.max_ms = ms
          end
        end
      end
    end
  end

  -- Convert to list, sort according to mode
  local all = {}
  for _, v in pairs(agg) do
    table.insert(all, v)
  end

  if sort_mode == 'execs' then
    table.sort(all, function(a, b)
      return a.count > b.count
    end)
  elseif sort_mode == 'rows' then
    table.sort(all, function(a, b)
      return a.total_rows > b.total_rows
    end)
  elseif sort_mode == 'ms' then
    table.sort(all, function(a, b)
      return a.max_ms > b.max_ms
    end)
  end

  -- Compute totals for summary
  local total_execs, total_rows = 0, 0
  for _, v in ipairs(all) do
    total_execs = total_execs + v.count
    total_rows = total_rows + v.total_rows
  end

  -- Prepare Top 5 block, always sorted by execution count
  local top5_sorted = {}
  for _, v in ipairs(all) do
    table.insert(top5_sorted, v)
  end
  table.sort(top5_sorted, function(a, b)
    return a.count > b.count
  end)

  local top5 = {}
  for i = 1, math.min(5, #top5_sorted) do
    local q = top5_sorted[i]
    local soql_str = q.soql:gsub('\n', ' ')
    if soql_truncate then
      soql_str = soql_str:gsub('([sS][eE][lL][eE][cC][tT]).-%s+([fF][rR][oO][mM])%s+', '%1 ... %2 ')
    end
    table.insert(top5, string.format('%d. %s | execs:%d | max %.2fms | rows:%d', i, soql_str, q.count, q.max_ms, q.total_rows))
  end

  local sort_label = ({
    execs = '-- Sorted by: Executions --',
    rows = '-- Sorted by: Rows --',
    ms = '-- Sorted by: Time --',
  })[sort_mode or 'execs'] or ''

  local flat, highlight_spans = {}, {}
  table.insert(flat, string.format('Total SOQL Executions: %d | Total Rows: %d', total_execs, total_rows))
  if #top5 > 0 then
    table.insert(flat, '---- Top 5 SOQL Statements ----')
    for _, l in ipairs(top5) do
      table.insert(flat, l)
    end
    table.insert(flat, '----------------------------------------')
  end
  table.insert(flat, sort_label)
  for idx, block in ipairs(all) do
    local prefix = ('%d. |'):format(idx)
    local code_row_str = block.code_row and ('[' .. block.code_row .. ']| ') or ''
    local index_start = #prefix
    local index_end = index_start + #code_row_str
    local soql_str = block.soql and block.soql or ''
    if soql_truncate then
      soql_str = soql_str:gsub('([sS][eE][lL][eE][cC][tT]).-%s+([fF][rR][oO][mM])%s+', '%1 ... %2 ')
    end
    local exec_str = 'execs:' .. block.count
    local ms_str = ('max %.2fms'):format(block.max_ms)
    local rows_str = 'rows:' .. table.concat(block.row_counts, '|')
    local line = prefix .. code_row_str .. soql_str .. ' | ' .. exec_str .. ' | ' .. ms_str .. ' | ' .. rows_str
    table.insert(flat, line)
    if #code_row_str > 0 then
      table.insert(highlight_spans, { line = #flat - 1, from = index_start, to = index_end - 1 })
    end
  end
  if #all == 0 then
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
---@return table, TreeNode[]
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
      local fullName = vim.trim(parts[#parts] or tag)
      local paren = fullName:find '%('
      if paren then
        return fullName:sub(1, paren - 1) .. '()'
      else
        return fullName
      end
    elseif tag == 'ENTERING_MANAGED_PKG' then
      return 'MANAGED CODE'
    elseif tag == 'SOQL_EXECUTE_BEGIN' then
      local soql = line:match '[SELECT].*'
      if soql and soql_truncate then
        soql = soql:gsub('([sS][eE][lL][eE][cC][tT]).-%s+([fF][rR][oO][mM])%s+', '%1 ... %2 ')
      end
      if soql and soql_truncate_where then
        soql = soql:gsub('%s+[wW][hH][eE][rR][eE]%s+.*', ' ...')
      end
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
        soql_count = 0, -- Initialize SOQL count
        dml_count = 0, -- Initialize DML count
      }
      table.insert(nodes, node)
      if node.parent then
        table.insert(node.parent.children, node)
      end
      if event_tag == 'SOQL_EXECUTE_BEGIN' then
        node.soql_count = node.soql_count + 1
      elseif event_tag == 'DML_BEGIN' then
        node.dml_count = node.dml_count + 1
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

  -- New aggregation for identical, childless siblings
  local function aggregate_identical_siblings_recursive(children)
    if not children or #children == 0 then
      return children
    end

    -- First, recurse on children of children
    for _, child in ipairs(children) do
      if child.children and #child.children > 0 then
        child.children = aggregate_identical_siblings_recursive(child.children)
      end
    end

    local aggregated_children = {}
    local i = 1
    while i <= #children do
      local current_node = children[i]
      if #current_node.children == 0 then -- Only aggregate leaf nodes
        local group_end = i
        while
          group_end + 1 <= #children
          and children[group_end + 1].name == current_node.name
          and children[group_end + 1].code_row == current_node.code_row
          and #children[group_end + 1].children == 0
        do
          group_end = group_end + 1
        end

        if group_end > i then
          local total_ns = 0
          local total_soql = 0
          local total_dml = 0
          local total_own_soql = 0
          local total_own_dml = 0
          for j = i, group_end do
            total_ns = total_ns + ((children[j].end_ns or children[j].start_ns) - children[j].start_ns)
            
          end
          local new_node = {
            tag = current_node.tag,
            name = current_node.name .. ' (x' .. (group_end - i + 1) .. ')',
            code_row = current_node.code_row,
            start_ns = current_node.start_ns,
            end_ns = current_node.start_ns + total_ns,
            children = {},
            parent = current_node.parent,
            expanded = false,
            line_idx = current_node.line_idx,
            soql_count = current_node.soql_count,
            dml_count = current_node.dml_count,
            own_soql_count = current_node.own_soql_count,
            own_dml_count = current_node.own_dml_count,
          }
          table.insert(aggregated_children, new_node)
          i = group_end + 1
        else
          table.insert(aggregated_children, current_node)
          i = i + 1
        end
      else
        table.insert(aggregated_children, current_node)
        i = i + 1
      end
    end
    return aggregated_children
  end
  roots = aggregate_identical_siblings_recursive(roots)

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

  local function aggregate_soql_dml(node)
    node.own_soql_count = 0
    node.own_dml_count = 0

    if node.children then
      for _, child in ipairs(node.children) do
        if child.tag == 'SOQL_EXECUTE_BEGIN' then
          node.own_soql_count = (node.own_soql_count or 0) + 1
        elseif child.tag == 'DML_BEGIN' then
          node.own_dml_count = (node.own_dml_count or 0) + 1
        end
        aggregate_soql_dml(child)
        node.soql_count = (node.soql_count or 0) + (child.soql_count or 0)
        node.dml_count = (node.dml_count or 0) + (child.dml_count or 0)
      end
    end
    node.has_soql_or_dml = (node.soql_count and node.soql_count > 0) or (node.dml_count and node.dml_count > 0)
  end

  for _, r in ipairs(roots) do
    collect_durations(r)
    aggregate_soql_dml(r)
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

  return longest, roots
end

---@param roots TreeNode[]
---@return string[]
local function extract_node_counts(roots)
  local counts = {}
  local function traverse(node)
    if node.has_soql_or_dml then
      local name = node.name:gsub(' %(x%d+)', '') -- remove (xN) from name
      local repetition_count = 1
      local rep_match = node.name:match('%(x(%d+)%)')
      if rep_match then
        repetition_count = tonumber(rep_match)
      end

      if not counts[name] then
        counts[name] = { total_count = 0, total_soql = 0, total_own_soql = 0, total_dml = 0, total_own_dml = 0 }
      end
      counts[name].total_count = counts[name].total_count + 1
      if counts[name].total_soql == 0 then
        counts[name].total_soql = (node.soql_count or 0)
      end
      if counts[name].total_own_soql == 0 then
        counts[name].total_own_soql = (node.own_soql_count or 0)
      end
      if counts[name].total_dml == 0 then
        counts[name].total_dml = (node.dml_count or 0)
      end
      if counts[name].total_own_dml == 0 then
        counts[name].total_own_dml = (node.own_dml_count or 0)
      end
    end
    if node.children then
      for _, child in ipairs(node.children) do
        traverse(child)
      end
    end
  end

  for _, root in ipairs(roots) do
    traverse(root)
  end

  local sorted_counts = {}
  for name, data in pairs(counts) do
    table.insert(sorted_counts, { name = name, total_count = data.total_count, total_soql = data.total_soql, total_own_soql = data.total_own_soql, total_dml = data.total_dml, total_own_dml = data.total_own_dml })
  end

  table.sort(sorted_counts, function(a, b)
    return a.total_count > b.total_count
  end)

  local lines = {}
  for i, item in ipairs(sorted_counts) do
    table.insert(lines, string.format('%d. %s: %d (SOQL:%d DML:%d) (SOQL:%d DML:%d)', i, item.name, item.total_count, item.total_soql, item.total_dml, item.total_own_soql, item.total_own_dml))
  end

  if #lines == 0 then
    return { 'No nodes with SOQL or DML found.' }
  end

  return lines
end

function M.analyzeLogs()
  ensure_teal_hl()
  local orig_lines = api.nvim_buf_get_lines(0, 0, -1, false)
  local ns = api.nvim_create_namespace 'apex_log_teal'

  local tab_bufs = {}
  local sort_modes = { 'execs', 'rows', 'ms' }
  local sort_mode_idx = 1
  local soql_sort_mode = sort_modes[sort_mode_idx]
  local user_debug_lines, userdebug_spans = extract_user_debug_blocks(orig_lines)
  local soql_lines, soql_spans = extract_soql_blocks(orig_lines, soql_sort_mode)

  local dml_lines, dml_spans = extract_dml_blocks(orig_lines)
  local exception_lines = extract_exception_blocks(orig_lines)

  -- Tree state
  local tree_longest, tree_roots
  local tree_lines, tree_line_map
  local hide_empty_nodes = false

  local function filter_tree_nodes(nodes)
    local filtered = {}
    for _, node in ipairs(nodes) do
      local has_soql_or_dml = (node.soql_count and node.soql_count > 0) or (node.dml_count and node.dml_count > 0)
      if hide_empty_nodes and not has_soql_or_dml then
        -- Skip this node if filtering and it has no SOQL/DML
      else
        -- Recursively filter children
        node.children = filter_tree_nodes(node.children)
        table.insert(filtered, node)
      end
    end
    return filtered
  end

  local function render_tree()
    local out_lines, out_map, out_highlights = {}, {}, {}
    local current_tree_roots = tree_roots
    if hide_empty_nodes then
      current_tree_roots = filter_tree_nodes(vim.deepcopy(tree_roots)) -- Deep copy to avoid modifying original tree_roots
    end

    local function render(node, depth)
      if hide_empty_nodes and not node.has_soql_or_dml then
        return
      end
      table.insert(out_map, node)
      local cr = node.code_row and (' [' .. node.code_row .. ']') or ''
      local indent = string.rep(' ', depth)
      local mark = (#node.children > 0) and (node.expanded and '▼ ' or '▶ ') or '  '
      local soql_dml_info = ''
      if (node.soql_count and node.soql_count > 0) or (node.dml_count and node.dml_count > 0) then
        soql_dml_info = string.format(' (SOQL:%d DML:%d)', node.soql_count or 0, node.dml_count or 0)
      end
      local own_soql_dml_info = ''
      if (node.own_soql_count and node.own_soql_count > 0) or (node.own_dml_count and node.own_dml_count > 0) then
        own_soql_dml_info = string.format(' (SOQL:%d DML:%d)', node.own_soql_count or 0, node.own_dml_count or 0)
      end

      local line = indent
        .. mark
        .. node.name
        .. cr
        .. soql_dml_info
        .. own_soql_dml_info
        .. string.format(' | %.2fms', node.duration)

      -- Store the highlight information for later application
      if (node.soql_count and node.soql_count > 0) or (node.dml_count and node.dml_count > 0) then
        local start_col = #indent + #mark + #node.name + #cr + 1 -- +1 for the space before (SOQL:...
        local end_col = start_col + #soql_dml_info - 1
        table.insert(out_highlights, { line_idx = #out_lines, start_col = start_col, end_col = end_col, hl_group = 'ApexLogRed' })
      end
      if (node.own_soql_count and node.own_soql_count > 0) or (node.own_dml_count and node.own_dml_count > 0) then
        local start_col = #indent + #mark + #node.name + #cr + #soql_dml_info + 1
        local end_col = start_col + #own_soql_dml_info - 1
        table.insert(
          out_highlights,
          { line_idx = #out_lines, start_col = start_col, end_col = end_col, hl_group = 'ApexLogTeal' }
        )
      end
      table.insert(out_lines, line)
      if node.expanded and node.children then
        for _, child in ipairs(node.children) do
          render(child, depth + 1)
        end
      end
    end

    if #tree_longest > 0 then
      for _, l in ipairs(tree_longest) do
        table.insert(out_lines, l)
        table.insert(out_map, { is_dummy = true })
      end
      table.insert(out_lines, '---- 10 Longest Operations ----')
      table.insert(out_map, { is_dummy = true })
    end
    for _, n in ipairs(tree_roots) do
      render(n, 0)
    end
    if #out_lines == 0 then
      table.insert(out_lines, 'No method stack information found.')
      table.insert(out_map, {})
    end
    return out_lines, out_map, out_highlights
  end

  local function update_tree_view()
    local new_lines, new_map, new_highlights = render_tree()
    tree_lines = new_lines
    tree_line_map = new_map
    api.nvim_buf_set_lines(tab_bufs[2], 0, -1, false, tree_lines)
    -- Apply highlights after setting lines
    api.nvim_buf_clear_namespace(tab_bufs[2], ns, 0, -1)
    for _, hl in ipairs(new_highlights) do
      api.nvim_buf_add_highlight(tab_bufs[2], ns, hl.hl_group, hl.line_idx, hl.start_col, hl.end_col)
    end
  end

  -- Initial tree creation
  tree_longest, tree_roots = extract_tree_blocks(orig_lines)
  local node_count_lines = extract_node_counts(tree_roots)

  local tab_titles = { 'User Debug', 'Method Tree', 'SOQL', 'DML', 'Exceptions', 'Node Counts' }

  for i, title in ipairs(tab_titles) do
    local buf = api.nvim_create_buf(false, true)
    if i == 1 then
      api.nvim_buf_set_lines(buf, 0, -1, false, user_debug_lines)
    elseif i == 2 then
      -- initial tree view is now handled by switch_tab
    elseif i == 3 then
      api.nvim_buf_set_lines(buf, 0, -1, false, soql_lines)
    elseif i == 4 then
      api.nvim_buf_set_lines(buf, 0, -1, false, dml_lines)
    elseif i == 5 then
      api.nvim_buf_set_lines(buf, 0, -1, false, exception_lines)
    elseif i == 6 then
      api.nvim_buf_set_lines(buf, 0, -1, false, node_count_lines)
    else
      api.nvim_buf_set_lines(buf, 0, -1, false, { 'This is the [' .. title .. '] tab.' })
    end
    tab_bufs[i] = buf
  end

  api.nvim_buf_set_keymap(tab_bufs[2], 'n', 'z', '', {
    noremap = true,
    nowait = true,
    callback = function()
      local win = api.nvim_get_current_win()
      local cur_line = api.nvim_win_get_cursor(win)[1]
      local node = tree_line_map[cur_line]
      if not node or node.is_dummy or not node.children or #node.children == 0 then
        return
      end
      node.expanded = not node.expanded
      update_tree_view()
      -- After re-rendering, the cursor might be off. We need to find the new line of the node.
      for i, n in ipairs(tree_line_map) do
        if n == node then
          api.nvim_win_set_cursor(win, { i, 0 })
          break
        end
      end
    end,
  })

  api.nvim_buf_set_keymap(tab_bufs[2], 'n', 'Z', '', {
    noremap = true,
    nowait = true,
    callback = function()
      local any_collapsed = false
      local function find_any_collapsed(nodes)
        for _, node in ipairs(nodes) do
          if any_collapsed then
            return
          end
          if #node.children > 0 and not node.expanded then
            any_collapsed = true
            return
          end
          if node.children and #node.children > 0 then
            find_any_collapsed(node.children)
          end
        end
      end
      find_any_collapsed(tree_roots)

      local new_state = any_collapsed
      local function set_all(nodes, state)
        for _, node in ipairs(nodes) do
          if #node.children > 0 then
            node.expanded = state
          end
          if node.children and #node.children > 0 then
            set_all(node.children, state)
          end
        end
      end
      set_all(tree_roots, new_state)
      update_tree_view()
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

  local function refresh_tree_buf()
    tree_longest, tree_roots = extract_tree_blocks(orig_lines)
    update_tree_view()
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
    if idx == 2 then
      update_tree_view()
    end
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
      api.nvim_buf_set_keymap(buf, 'n', 't', '', {
        noremap = true,
        nowait = true,
        callback = function()
          soql_truncate = not soql_truncate
          refresh_soql_buf()
          refresh_tree_buf()
        end,
      })
    elseif i == 2 or i == 6 then
      -- Method Tree tab and Node Counts tab: toggle SOQL truncation with 't'
      api.nvim_buf_set_keymap(buf, 'n', 't', '', {
        noremap = true,
        nowait = true,
        callback = function()
          soql_truncate = not soql_truncate
          refresh_tree_buf()
          refresh_soql_buf()
        end,
      })
      api.nvim_buf_set_keymap(buf, 'n', 'T', '', {
        noremap = true,
        nowait = true,
        callback = function()
          soql_truncate_where = not soql_truncate_where
          refresh_tree_buf()
        end,
      })
      api.nvim_buf_set_keymap(buf, 'n', 's', '', {
        noremap = true,
        nowait = true,
        callback = function()
          hide_empty_nodes = not hide_empty_nodes
          refresh_tree_buf()
        end,
      })
    end
  end
end

return M
