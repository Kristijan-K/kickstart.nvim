local function open_or_create_weekly_note()
  local Path = require 'obsidian.path'

  -- Get current week info
  local today = os.date '*t'
  local year = today.year
  local week = os.date '!%V' -- ISO 8601 week number (01–53)

  local filename = string.format('Week-%s-%s.md', year, week)
  local full_path = Path:new(vim.fn.expand '~/Obsidian/Weekly/' .. '/' .. filename)

  -- Check if note already exists
  if full_path:exists() then
    vim.cmd('e ' .. full_path.filename)
  else
    -- Create and open the new weekly note file
    vim.cmd('e ' .. full_path.filename)

    -- Insert template (after file loads)
    vim.defer_fn(function()
      vim.cmd 'ObsidianTemplate Weekly.md'
    end, 50)
  end
end

local function open_obsidian_today()
  vim.cmd 'ObsidianToday'
end

local function new_obsidian_document_with_template(template, location)
  local Path = require 'obsidian.path'

  vim.ui.input({ prompt = 'Enter new note title: ' }, function(title)
    if not title or title == '' then
      return
    end

    -- Slugify the filename
    local slug = title:gsub(' ', '-'):gsub('[^%w%-]', ''):lower()
    local filename = slug .. '.md'

    -- Define your desired folder (e.g., Inbox in Work vault)
    local note_path = Path:new(vim.fn.expand('~/Obsidian/' .. location .. '/' .. filename))

    -- Open the file (create if doesn't exist)
    vim.cmd('e ' .. note_path.filename)

    -- Insert the Note.md template
    vim.defer_fn(function()
      local cmd = 'ObsidianTemplate ' .. template
      vim.cmd(cmd)
    end, 50)
  end)
end

local function new_obsidian_note_with_template()
  new_obsidian_document_with_template('Note.md', '00-Inbox')
end

local function new_obsidian_presentation_with_template()
  new_obsidian_document_with_template('Presentation.md', 'Presentation')
end

-- Lua function to insert a template by filename
local function insert_obsidian_template(template_name)
  -- Define the full path to the template file
  local template_path = '~/Obsidian/Templates/' .. template_name .. '.md'
  template_path = vim.fn.expand(template_path)

  local lines = vim.fn.readfile(template_path)
  if not lines or vim.tbl_isempty(lines) then
    vim.notify("Template '" .. template_name .. "' not found or is empty.", vim.log.levels.WARN)
    return
  end

  -- Insert the template content into the current buffer
  vim.api.nvim_put(lines, 'l', true, true)
end

-- Keymap to insert Todo.md template with Alt+t
vim.keymap.set('n', '<A-t>', function()
  insert_obsidian_template 'Todo'
end, { desc = 'Insert Todo.md template' })

vim.keymap.set('n', '<leader>on', new_obsidian_note_with_template, { desc = 'New note from Note.md template' })
vim.keymap.set('n', '<leader>op', new_obsidian_presentation_with_template, { desc = 'New Preentation from Presentation.md template' })
vim.keymap.set('n', '<leader>od', open_obsidian_today, { desc = "Open today's daily note" })

vim.keymap.set('n', '<leader>ow', open_or_create_weekly_note, { desc = 'Open/Create Weekly Note from Template' })
