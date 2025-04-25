local M = {}

local function add_linees_to_buf(buf, lines)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_height(buf, #lines)
end

local function create_floating_window(config, enter)
  if enter == nil then
    enter = false
  end
  if config == nil then
    -- Get size of current window
    local width = 100
    local height = 10
    -- Center the floating window within current window
    local col = math.floor((vim.o.columns - width) / 2)
    local row = math.floor((vim.o.lines - height) / 2)
    -- Floating window options
    config = {
      style = 'minimal',
      relative = 'win',
      width = width,
      height = height,
      row = row,
      col = col,
      border = 'rounded',
    }
  end
  local buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer
  local win = vim.api.nvim_open_win(buf, enter or false, config)
  vim.keymap.set('n', '<Esc>', function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf })

  vim.keymap.set('n', '<C-c>', function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf })

  return { buf = buf, win = win }
end

local output_lines = {}

M.job_call = function(cmd, msg, err_msg, cb)
  output_lines = {}

  local float = create_floating_window()

  vim.fn.jobstart(cmd, {

    stdout_buffered = false,
    stderr_buffered = false,

    on_stdout = function(_, data, _)
      if data and #data > 0 then
        vim.list_extend(output_lines, data)

        filtered = vim.tbl_filter(function(line)
          return line and line ~= ''
        end, output_lines)
        vim.api.nvim_buf_set_lines(float.buf, 0, -1, false, output_lines)
      end
    end,

    on_stderr = function(_, data, _)
      if data and #data > 0 then
        for i, line in ipairs(data) do
          table.insert(output_lines, 'ERR: ' .. line)
        end

        filtered = vim.tbl_filter(function(line)
          return line and line ~= ''
        end, output_lines)

        vim.api.nvim_buf_set_lines(float.buf, 0, -1, false, output_lines)
      end
    end,

    on_exit = function(_, code)
      filtered = vim.tbl_filter(function(line)
        return line and line ~= ''
      end, output_lines)

      vim.api.nvim_buf_set_lines(float.buf, 0, -1, false, output_lines)
      if code == 0 and cb ~= nil then
        cb()
      end
    end,
  })
end

M.sf = function()
  local relpath = vim.fn.expand '%:.'
  vim.notify(string.format('sf project deploy start --source-dir %s', relpath), vim.log.levels.INFO)
  M.job_call(string.format('sf project deploy start --source-dir %s', relpath), nil, nil, nil)
end

-- Map a command to the function
vim.api.nvim_command 'command! HelloWorld lua require("custom/plugins").sf()'

return M
