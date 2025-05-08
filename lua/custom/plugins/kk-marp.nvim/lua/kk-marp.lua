local M = {}

M.start_presentation = function()
  local fullpath = vim.fn.expand '%:p'
  local dir = vim.fn.expand '%:p:h'
  local filename_no_ext = vim.fn.expand '%:t:r'
  local output_file = dir .. '\\' .. filename_no_ext .. '.html'

  -- Create full marp and open commands
  local cmd_marp = 'marp ' .. fullpath .. ' -o ' .. output_file .. ''
  local cmd_open = 'start  ' .. output_file .. ''

  -- Notify what we're about to run
  vim.schedule(function()
    vim.notify('Running Marp command:\n' .. cmd_marp, vim.log.levels.INFO)
  end)

  local marpOut = vim.fn.system { 'marp', fullpath, '-o', output_file }
  vim.cmd('!start "" "file:///' .. output_file .. '"')
end

return M
