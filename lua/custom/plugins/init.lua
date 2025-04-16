local M = {}

-- Utility to show a floating popup with merged job output
local function show_popup(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.min(#lines, math.floor(vim.o.lines * 0.6))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
  })

  -- Map <Esc> and <C-c> to close the window
  vim.keymap.set('n', '<Esc>', function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, nowait = true, silent = true })

  vim.keymap.set('n', '<C-c>', function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, nowait = true, silent = true })

  -- Optional: make the buffer modifiable and navigable
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
end

-- Buffer job output here
local output_lines = {}

M.job_call = function(cmd, msg, err_msg, cb)
  job_failed = false
  vim.fn.jobstart(cmd, {

    stdout_buffered = true,
    stderr_buffered = true,

    on_stdout = function(_, data, _)
      if data and #data > 0 then
        vim.list_extend(output_lines, data)
      end
    end,

    on_stderr = function(_, data, _)
      if data and #data > 0 then
        for i, line in ipairs(data) do
          table.insert(output_lines, 'ERR: ' .. line)
        end
      end
    end,

    on_exit = function(_, code)
      local filtered = vim.tbl_filter(function(line)
        return line and line ~= ''
      end, output_lines)

      vim.schedule(function()
        show_popup(filtered)
      end)
      if code == 0 and cb ~= nil then
        cb()
      end
    end,
  })
end

M.sf = function()
  local filepath = vim.fn.expand '%:p'
  vim.notify('sfdx force:source:deploy -p [%s]' .. filepath, vim.log.levels.INFO)
  M.job_call(string.format('sfdx force:source:deploy -p [%s]', filepath), nil, nil, nil)
end

-- Map a command to the function
vim.api.nvim_command 'command! HelloWorld lua require("custom/plugins").sf()'

return M
