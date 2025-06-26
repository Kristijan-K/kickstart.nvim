local M = {}

local function create_floating_window(opts, enter)
  if enter == nil then
    enter = false
  end
  local width = 120
  local height = 35
  -- Center the floating window within current window
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)
  -- Floating window options
  local config = {
    style = 'minimal',
    relative = 'win',
    width = width,
    height = height,
    row = row,
    col = col,
    border = 'rounded',
  }
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

M.job_call = function(cmd, msg, config)
  output_lines = {}

  local float = create_floating_window(config)

  local filter_lines = function()
    local filtered = vim.tbl_filter(function(line)
      return line and line ~= ''
    end, output_lines)
    local max_lines = 12
    vim.api.nvim_buf_set_lines(float.buf, 0, -1, false, output_lines)
    vim.api.nvim_set_current_win(float.win)
  end

  vim.fn.jobstart({ 'powershell.exe', '-Command', cmd }, {

    stdout_buffered = false,
    stderr_buffered = false,

    on_stdout = function(_, data, _)
      if data and #data > 0 then
        vim.list_extend(output_lines, data)
        filter_lines()
      end
    end,

    on_stderr = function(_, data, _)
      if data and #data > 0 then
        for i, line in ipairs(data) do
          table.insert(output_lines, line)
        end
        filter_lines()
      end
    end,

    on_exit = function(_, code)
      filter_lines()
      if config and config.reloadFile then
        vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter' }, {
          command = 'checktime',
        })
      end

      if config.keepOpen ~= true then
        vim.defer_fn(function()
          vim.api.nvim_win_close(float.win, true)
        end, 3000)
      end
    end,
  })
end

M.sf_execute = function(config)
  local relpath = vim.fn.expand '%:.'
  if config.path ~= nil then
    relpath = config.path
  end
  local cmdString = ''
  if config.isTest == true then
    relpath = vim.fn.expand '%:t:r'
    cmdString = string.format(config.cmd .. ' 2>&1', relpath)
    cmdString = cmdString:gsub('"', '\\"')
  else
    cmdString = string.format(config.cmd .. ' %s 2>&1', relpath)
  end
  vim.notify(cmdString, vim.log.levels.INFO)
  M.job_call(cmdString, nil, config)
end

return M
