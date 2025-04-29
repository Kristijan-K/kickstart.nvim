local M = {}

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

M.job_call = function(cmd, msg, config)
  output_lines = {}

  local float = create_floating_window()

  local filter_lines = function()
    local filtered = vim.tbl_filter(function(line)
      return line and line ~= ''
    end, output_lines)

    while #output_lines > 12 do
      table.remove(output_lines, 1) -- Remove from the front
    end
    vim.api.nvim_buf_set_lines(float.buf, 0, -1, false, output_lines)
    vim.api.nvim_set_current_win(float.win)
  end

  vim.fn.jobstart(cmd, {

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

      vim.defer_fn(function()
        vim.api.nvim_win_close(float.win, true)
      end, 3000)
    end,
  })
end

M.sf_execute = function(config)
  local relpath = vim.fn.expand '%:.'
  if config.path ~= nil then
    relpath = config.path
  end
  vim.notify(string.format(config.cmd .. ' %s', relpath), vim.log.levels.INFO)
  M.job_call(string.format(config.cmd .. ' %s 2>&1', relpath), nil, config)
end

return M
