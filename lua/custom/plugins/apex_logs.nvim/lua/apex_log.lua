local M = {}

--- @class LogEntry
--- @field timestamp string
--- @field level string
--- @field message string
--- @field raw_lines string[]
local LogEntry = {}
LogEntry.__index = LogEntry

--- @param timestamp string
--- @param level string
--- @param message string
--- @param raw_lines string[]
--- @return LogEntry
function LogEntry.new(timestamp, level, message, raw_lines)
  return setmetatable({
    timestamp = timestamp,
    level = level,
    message = message,
    raw_lines = raw_lines,
  }, LogEntry)
end

--- @class Stack
--- @field items any[]
local Stack = {}
Stack.__index = Stack

--- @return Stack
function Stack.new()
  return setmetatable({ items = {} }, Stack)
end

--- @param item any
function Stack:push(item)
  table.insert(self.items, item)
end

--- @return any | nil
function Stack:pop()
  return table.remove(self.items)
end

--- @return any | nil
function Stack:peek()
  return self.items[#self.items]
end

--- @return boolean
function Stack:is_empty()
  return #self.items == 0
end

--- @class MethodCallNode
--- @field name string
--- @field timestamp_start string
--- @field timestamp_end string|nil
--- @field children MethodCallNode[]
--- @field parent MethodCallNode|nil
local MethodCallNode = {}
MethodCallNode.__index = MethodCallNode

--- @param name string
--- @param timestamp_start string
--- @param parent MethodCallNode|nil
--- @return MethodCallNode
function MethodCallNode.new(name, timestamp_start, parent)
  return setmetatable({
    name = name,
    timestamp_start = timestamp_start,
    timestamp_end = nil,
    children = {},
    parent = parent,
  }, MethodCallNode)
end

--- @param child MethodCallNode
function MethodCallNode:add_child(child)
  table.insert(self.children, child)
end

--- @param log_entries LogEntry[]
--- @return MethodCallNode root
local function build_call_tree(log_entries)
  local root = MethodCallNode.new('root', log_entries[1].timestamp, nil)
  local stack = Stack.new()
  stack:push(root)

  for _, entry in ipairs(log_entries) do
    if entry.message:match '^Starting method (.+)' then
      local method_name = entry.message:match '^Starting method (.+)'
      local parent = stack:peek()
      local node = MethodCallNode.new(method_name, entry.timestamp, parent)
      parent:add_child(node)
      stack:push(node)
    elseif entry.message:match '^Ending method (.+)' then
      local method_name = entry.message:match '^Ending method (.+)'
      local node = stack:pop()
      if node and node.name == method_name then
        node.timestamp_end = entry.timestamp
      end
    end
  end

  return root
end

M.analyzeLogs = function()
  local a = 1
end

return M
